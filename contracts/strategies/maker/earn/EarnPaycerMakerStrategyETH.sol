// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

import "./EarnPaycerMakerStrategy.sol";

//solhint-disable no-empty-blocks
contract EarnPaycerMakerStrategyETH is EarnPaycerMakerStrategy {
    string public constant NAME = "Earn-Paycer-Maker-Strategy-ETH";
    string public constant VERSION = "3.0.16";

    constructor(
        address _pool,
        address _cm,
        address _swapManager,
        address _vPool
    ) EarnPaycerMakerStrategy(_pool, _cm, _swapManager, _vPool, "ETH-C", DAI) {}
}
