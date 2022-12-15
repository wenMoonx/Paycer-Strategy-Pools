// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

import "../../interfaces/paycer/IPoolAccountant.sol";
import "./VFRPool.sol";

// solhint-disable no-empty-blocks
contract VFRStablePool is VFRPool {
    string public constant VERSION = "3.0.4";

    uint256 public targetAPY;
    uint256 public startTime;
    uint256 public initialPricePerShare;

    // Spot predictedAPY (can't be > targetAPY)
    uint256 public predictedAPY;

    // Accumulator for Time-weighted average Predicted APY for auto-retargeting
    uint256 public accPredictedAPY;
    uint256 public lastObservationBlock;
    uint256 public predictionStartBlock;

    uint256 public tolerance;
    uint256 public lockPeriod;

    // user address to last deposit timestamp mapping
    mapping(address => uint256) public depositTimestamp;

    bool public depositsHalted;

    event ToleranceSet(uint256 tolerance);
    event LockPeriodSet(uint256 lockPeriod);
    event Retarget(uint256 targetAPY, uint256 tolerance);

    constructor(
        string memory _name,
        string memory _symbol,
        address _token
    ) VFRPool(_name, _symbol, _token) {
        lockPeriod = 7 days;
        predictionStartBlock = block.number;
        lastObservationBlock = block.number;
    }

    modifier onlyWithdrawUnlocked(address _sender) {
        require(block.timestamp >= depositTimestamp[_sender] + lockPeriod, "lock-period-not-expired");
        _;
    }

    function setLockPeriod(uint256 _newLockPeriod) external onlyGovernor {
        require(_newLockPeriod != lockPeriod, "same-lock-period");
        lockPeriod = _newLockPeriod;
    }

    function setTolerance(uint256 _tolerance) external onlyGovernor {
        require(_tolerance != 0, "tolerance-value-is-zero");
        require(_tolerance != tolerance, "same-tolerance-value");
        tolerance = _tolerance;
        emit ToleranceSet(_tolerance);
    }

    function retarget(uint256 _apy, uint256 _tolerance) external onlyGovernor {
        _retarget(_apy, _tolerance);
    }

    // Moves Target APY by a tolerance step according to time-weighted Predicted APY
    // Make sure to collect enough checkpoints before for a accurate retargeting
    function autoRetarget() external onlyKeeper {
        uint256 _avgPredictedAPY = avgPredictedAPY();

        // Make sure to have at least a checkpoint since last retarget
        require(_avgPredictedAPY > 0, "invalid-avg-predicted-apy");

        if (_avgPredictedAPY > targetAPY + tolerance) {
            _retarget(targetAPY + tolerance, tolerance);
        } else if (_avgPredictedAPY < targetAPY - tolerance) {
            _retarget(targetAPY - tolerance, tolerance);
        }
        // if _avgPredictedAPY is within targetAPY (+/- ~ tolerance) do nothing
        // Goal is to keep rate as fixed as possible
    }

    function checkpoint() external onlyKeeper {
        address[] memory strategies = getStrategies();

        uint256 profits;
        uint256 loss;
        for (uint256 i = 0; i < strategies.length; i++) {
            (, uint256 fee, , , uint256 totalDebt, , , ) = IPoolAccountant(poolAccountant).strategy(strategies[i]);
            uint256 totalValue = IStrategy(strategies[i]).totalValueCurrent();
            if (totalValue > totalDebt) {
                uint256 totalProfits = totalValue - totalDebt;
                uint256 actualProfits = totalProfits - ((totalProfits * fee) / MAX_BPS);
                profits += actualProfits;
            } else {
                loss += (totalDebt - totalValue);
            }
        }

        if (buffer != address(0)) {
            // This should take into account that an interest fee is taken from the amount in the buffer
            // (however, the interest fee depends on which strategy will request funds from the buffer)
            profits += token.balanceOf(buffer);
        }

        // Profit will be reduced, if any strategy is expected to report loss.
        if (loss != 0) {
            profits = profits > loss ? profits - loss : 0;
        }

        // Calculate the price per share if the above profits were to be reported
        uint256 predictedPricePerShare;
        if (totalSupply() == 0 || totalValue() == 0) {
            predictedPricePerShare = convertFrom18(1e18);
        } else {
            predictedPricePerShare = ((totalValue() + profits) * 1e18) / totalSupply();
        }

        if (predictedPricePerShare < initialPricePerShare) {
            predictedAPY = 0;
        } else {
            // Predict the APY based on the unreported profits of all strategies
            predictedAPY =
                ((predictedPricePerShare - initialPricePerShare) * (1e18 * 365 * 24 * 3600)) /
                (initialPricePerShare * (block.timestamp - startTime));

            // Updates the time-weighted average Predicted APY accumulator
            accPredictedAPY += predictedAPY * (block.number - lastObservationBlock);
            lastObservationBlock = block.number;
            // Although the predicted APY can be greater than the target APY due to the funds
            // available in the buffer, the strategies will make sure to never send more funds
            // to the pool than the amount needed to cover the target APY
            predictedAPY = predictedAPY > targetAPY ? targetAPY : predictedAPY;
        }

        // The predicted APY must be within the target APY by no more than the current tolerance
        depositsHalted = targetAPY - predictedAPY > tolerance;
    }

    // Gets the time-weighted average Predicted APY since last retarget
    // It updates every checkpoint since last retarget (more checkpoints -> better prediction)
    function avgPredictedAPY() public view returns (uint256 _avgPredictedAPY) {
        uint256 _elapsedBlocks = lastObservationBlock - predictionStartBlock;
        _avgPredictedAPY = (_elapsedBlocks != 0) ? accPredictedAPY / _elapsedBlocks : 0;
    }

    function targetPricePerShare() public view returns (uint256) {
        return
            initialPricePerShare +
            ((initialPricePerShare * targetAPY * (block.timestamp - startTime)) / (1e18 * 365 * 24 * 3600));
    }

    function amountToReachTarget(address _strategy) public view returns (uint256) {
        uint256 fromPricePerShare = pricePerShare();
        uint256 toPricePerShare = targetPricePerShare();
        if (fromPricePerShare < toPricePerShare) {
            (, uint256 fee, , , , , , ) = IPoolAccountant(poolAccountant).strategy(_strategy);
            uint256 fromTotalValue = (fromPricePerShare * totalSupply()) / 1e18;
            uint256 toTotalValue = (toPricePerShare * totalSupply()) / 1e18;
            uint256 amountWithoutFee = toTotalValue - fromTotalValue;
            // Take into account the performance fee of the strategy
            return (amountWithoutFee * MAX_BPS) / (MAX_BPS - fee);
        }
        return 0;
    }

    function _retarget(uint256 _apy, uint256 _tolerance) internal {
        // eg. 100% APY -> 1 * 1e18 = 1e18
        //     5% APY -> 0.05 * 1e18 = 5e16
        targetAPY = _apy;
        startTime = block.timestamp;
        initialPricePerShare = pricePerShare();
        predictedAPY = _apy;
        // Only allow deposits if at the last rebalance the pool's actual APY
        // was not behind the target APY for more than 'tolerance'. Probably
        // a better way to set this is dynamically based on how long the pool
        // has been running for.
        tolerance = _tolerance;
        emit Retarget(_apy, _tolerance);

        // Restart time-weighted PredictedAPY calculation
        lastObservationBlock = block.number;
        predictionStartBlock = block.number;
        accPredictedAPY = 0;
    }

    function _deposit(uint256 _amount) internal override {
        require(!depositsHalted, "pool-under-target");
        depositTimestamp[_msgSender()] = block.timestamp;
        super._deposit(_amount);
    }

    function _withdraw(uint256 _shares) internal override onlyWithdrawUnlocked(_msgSender()) {
        super._withdraw(_shares);
    }

    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal override onlyWithdrawUnlocked(_sender) {
        super._transfer(_sender, _recipient, _amount);
    }
}
