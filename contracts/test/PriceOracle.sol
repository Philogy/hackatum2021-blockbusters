//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPriceOracle.sol";

contract PriceOracleTest is IPriceOracle, Ownable {
    mapping(address => uint256) virtualPrice;
    function getVirtualPrice(address token)
        view
        external
        override
        returns (uint256) {
        if (virtualPrice[token] == 0) {
            return 1 ether;
        } else {
            return virtualPrice[token];
        }
    }

    function setVirtualPrice(address token, uint256 newPrice) external onlyOwner returns(bool) {
        require(newPrice != virtualPrice[token], "new and old prices are the same");
        virtualPrice[token] = newPrice;
        return true;
    }
}