// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFlashloanProvider {
    function requestFlashloan(IERC20 _token, uint256 _amount) external;
}
