// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

import "./EarnRariFuseStrategy.sol";
import "../../../interfaces/token/IToken.sol";

// solhint-disable no-empty-blocks
/// @title Deposit ETH/WETH in RariFuse and earn interest in DAI.
contract EarnRariFuseStrategyETH is EarnRariFuseStrategy {
    // DAI = 0x6b175474e89094c44da98b954eedeac495271d0f
    constructor(
        address _pool,
        address _swapManager,
        uint256 _fusePoolId
    )
        EarnRariFuseStrategy(
            _pool,
            _swapManager,
            _fusePoolId,
            0x6B175474E89094C44Da98b954EedeAC495271d0F // DAI
        )
    {}

    function migrateFusePool(uint256 _newPoolId) external override onlyKeeper {
        address _newCToken = _cTokenByUnderlying(_newPoolId, address(collateralToken));
        require(address(cToken) != _newCToken, "same-fuse-pool");
        require(cToken.redeem(cToken.balanceOf(address(this))) == 0, "withdraw-from-fuse-pool-failed");
        CToken(_newCToken).mint{value: address(this).balance}();
        emit FusePoolChanged(_newPoolId, address(cToken), _newCToken);
        cToken = CToken(_newCToken);
        receiptToken = _newCToken;
        fusePoolId = _newPoolId;
    }

    /// @dev Only receive ETH from either cToken or WETH
    receive() external payable {
        require(msg.sender == address(cToken) || msg.sender == WETH, "not-allowed-to-send-ether");
    }

    /**
     * @dev This hook get called after collateral is redeemed from RariFuse
     * Paycer deals in WETH as collateral so convert ETH to WETH
     */
    function _afterRedeem() internal override {
        TokenLike(WETH).deposit{value: address(this).balance}();
    }

    /**
     * @dev During reinvest we have WETH as collateral but RariFuse accepts ETH.
     * Withdraw ETH from WETH before calling mint in RariFuse.
     */
    function _reinvest() internal override {
        uint256 _collateralBalance = collateralToken.balanceOf(address(this));
        if (_collateralBalance != 0) {
            TokenLike(WETH).withdraw(_collateralBalance);
            cToken.mint{value: _collateralBalance}();
        }
    }
}
