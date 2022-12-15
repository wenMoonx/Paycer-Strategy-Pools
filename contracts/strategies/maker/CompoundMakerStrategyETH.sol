// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

import "./CompoundMakerStrategy.sol";
import "../../interfaces/token/IToken.sol";

//solhint-disable no-empty-blocks
contract CompoundMakerStrategyETH is CompoundMakerStrategy {
    string public constant NAME = "Compound-Maker-Strategy-ETH";
    string public constant VERSION = "3.0.0";

    // cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643
    constructor(
        address _pool,
        address _cm,
        address _swapManager
    ) CompoundMakerStrategy(_pool, _cm, _swapManager, 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643, "ETH-C") {}
}
