// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;
import "../Earn.sol";
import "../../interfaces/paycer/IPaycerPool.sol";

/// @title This Earn strategy will deposit collateral token in a Paycer Grow Pool
/// and converts the yield to another Drip Token
abstract contract EarnPaycerStrategy is Strategy, Earn {
    using SafeERC20 for IERC20;
    address internal constant VSP = 0x1b40183EFB4Dd766f11bDa7A7c3AD8982e998421;
    IPaycerPool internal immutable vToken;

    constructor(
        address _pool,
        address _swapManager,
        address _receiptToken,
        address _dripToken
    ) Strategy(_pool, _swapManager, _receiptToken) Earn(_dripToken) {
        require(_receiptToken != address(0), "vToken-address-is-zero");
        vToken = IPaycerPool(_receiptToken);
    }

    /**
     * @notice Calculate total value using underlying vToken
     * @dev Report total value in collateral token
     */
    function totalValue() public view override returns (uint256 _totalValue) {
        _totalValue = _getCollateralBalance();
    }

    function isReservedToken(address _token) public view override returns (bool) {
        return _token == address(vToken);
    }

    /// @notice Approve all required tokens
    function _approveToken(uint256 _amount) internal virtual override {
        collateralToken.safeApprove(pool, _amount);
        collateralToken.safeApprove(address(vToken), _amount);
        for (uint256 i = 0; i < swapManager.N_DEX(); i++) {
            IERC20(VSP).safeApprove(address(swapManager.ROUTERS(i)), _amount);
            collateralToken.safeApprove(address(swapManager.ROUTERS(i)), _amount);
        }
    }

    /**
     * @notice Before migration hook.
     * @param _newStrategy Address of new strategy.
     */
    //solhint-disable-next-line no-empty-blocks
    function _beforeMigration(address _newStrategy) internal override {}

    /// @notice Withdraw collateral to payback excess debt
    function _liquidate(uint256 _excessDebt) internal override returns (uint256 _payback) {
        if (_excessDebt != 0) {
            _payback = _safeWithdraw(_excessDebt);
        }
    }

    /**
     * @notice Calculate earning and withdraw it from Paycer Grow.
     * @param _totalDebt Total collateral debt of this strategy
     * @return profit in collateral token
     */
    function _realizeProfit(uint256 _totalDebt) internal virtual override returns (uint256) {
        _claimRewardsAndConvertTo(address(dripToken));
        uint256 _collateralBalance = _getCollateralBalance();
        if (_collateralBalance > _totalDebt) {
            _withdrawHere(_collateralBalance - _totalDebt);
        }
        _convertCollateralToDrip();
        _forwardEarning();
        return 0;
    }

    /// @notice Claim VSP rewards in underlying Grow Pool, if any
    function _claimRewardsAndConvertTo(address _toToken) internal virtual override {
        uint256 _vspAmount = IERC20(VSP).balanceOf(address(this));
        if (_vspAmount != 0) {
            _safeSwap(VSP, _toToken, _vspAmount, 1);
        }
    }

    /**
     * @notice Calculate realized loss.
     * @return _loss Realized loss in collateral token
     */
    function _realizeLoss(uint256 _totalDebt) internal view override returns (uint256 _loss) {
        uint256 _collateralBalance = _getCollateralBalance();

        if (_collateralBalance < _totalDebt) {
            _loss = _totalDebt - _collateralBalance;
        }
    }

    /// @notice Deposit collateral in Paycer Grow
    function _reinvest() internal virtual override {
        uint256 _collateralBalance = collateralToken.balanceOf(address(this));
        if (_collateralBalance != 0) {
            vToken.deposit(_collateralBalance);
        }
    }

    /// @dev Withdraw collateral and transfer it to pool
    function _withdraw(uint256 _amount) internal override {
        _safeWithdraw(_amount);
        collateralToken.safeTransfer(pool, collateralToken.balanceOf(address(this)));
    }

    /**
     * @notice Safe withdraw will make sure to check asking amount against available amount.
     * @param _amount Amount of collateral to withdraw.
     * @return Actual collateral withdrawn
     */
    function _safeWithdraw(uint256 _amount) internal returns (uint256) {
        uint256 _collateralBalance = _getCollateralBalance();
        // Get minimum of _amount and _collateralBalance
        return _withdrawHere(_amount < _collateralBalance ? _amount : _collateralBalance);
    }

    /// @dev Withdraw collateral here. Do not transfer to pool
    function _withdrawHere(uint256 _amount) internal returns (uint256) {
        uint256 _collateralBefore = collateralToken.balanceOf(address(this));
        vToken.whitelistedWithdraw(_convertToShares(_amount));
        return collateralToken.balanceOf(address(this)) - _collateralBefore;
    }

    /// @dev Gets collateral balance deposited into Paycer Grow Pool
    function _getCollateralBalance() internal view returns (uint256) {
        uint256 _totalSupply = vToken.totalSupply();
        // avoids division by zero error when pool is empty
        return (_totalSupply != 0) ? (vToken.totalValue() * vToken.balanceOf(address(this))) / _totalSupply : 0;
    }

    /// @dev Converts a collateral amount in its relative shares for Paycer Grow Pool
    function _convertToShares(uint256 _collateralAmount) internal view returns (uint256) {
        uint256 _totalValue = vToken.totalValue();
        return (_totalValue != 0) ? (_collateralAmount * vToken.totalSupply()) / _totalValue : 0;
    }
}
