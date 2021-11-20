// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../Bank.sol";

contract VBTestBank is Bank {
    using SafeMath for uint256;

    uint256 internal lastRealBlock;
    uint256 internal virtualBlockNumber;

    constructor(address _priceOracle, address _hakToken)
        Bank(_priceOracle, _hakToken)
    {
        virtualBlockNumber = block.number;
    }

    function advanceBlocks(uint256 _blocks) external {
        virtualBlockNumber = virtualBlockNumber.add(_blocks);
        lastRealBlock = block.number;
    }

    function _getBlockNumber() internal override view returns (uint256) {
        uint256 realBlockDelta = block.number.sub(lastRealBlock);
        return virtualBlockNumber.add(realBlockDelta);
    }
}
