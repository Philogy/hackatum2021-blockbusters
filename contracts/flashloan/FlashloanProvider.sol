// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../lib/Constants.sol";
import "../interfaces/IFlashloanProvider.sol";
import "../interfaces/IFlashloanRecipient.sol";

contract FlashloanProvider is ReentrancyGuard, Ownable, IFlashloanProvider {
    using Address for address payable;
    using SafeERC20 for IERC20;

    mapping(address => bool) public authorizedFlashloanUser;

    // solhint-disable-next-line no-empty-blocks
    constructor() Ownable() ReentrancyGuard() { }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function setFlashloanUser(address _user, bool _authorized) external onlyOwner {
        authorizedFlashloanUser[_user] = _authorized;
    }

    function requestFlashloan(IERC20 _token, uint256 _amount)
        external override nonReentrant
    {
        require(authorizedFlashloanUser[msg.sender], "Flash: Unauthorized flashloan");
        uint256 balanceBefore;
        uint256 balanceAfter;
        if (_token == Constants.PSEUDO_ETH) {
            balanceBefore = address(this).balance;
            payable(msg.sender).sendValue(_amount);
            IFlashloanRecipient(msg.sender).receiveFlashloan(_token, _amount);
            balanceAfter = address(this).balance;
        } else {
            balanceBefore = _token.balanceOf(address(this));
            _token.safeTransfer(msg.sender, _amount);
            IFlashloanRecipient(msg.sender).receiveFlashloan(_token, _amount);
            balanceAfter = _token.balanceOf(address(this));
        }
        require(balanceAfter == balanceBefore, "Flash: Not returned");
    }
}
