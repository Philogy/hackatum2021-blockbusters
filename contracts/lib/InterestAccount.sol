// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

library InterestAccount {
    using SafeMath for uint256;

    struct Account {
        uint256 balance;
        uint256 interest;
        uint256 lastInterestBlock;
    }

    function getNewInterest(
        Account storage _account,
        uint256 _interestRate,
        uint256 _blockNumber
    ) internal view returns (uint256) {
        uint256 passedBlocks = _blockNumber.sub(_account.lastInterestBlock);
        uint256 newInterest =
            _account.balance.mul(_interestRate).mul(passedBlocks).div(1e4);
        return newInterest;
    }

    function getTotalInterest(
        Account storage _account,
        uint256 _interestRate,
        uint256 _blockNumber
    ) internal view returns (uint256) {
        uint256 newInterest = getNewInterest(
            _account,
            _interestRate,
            _blockNumber
        );
        return _account.interest.add(newInterest);
    }

    function getTotalBalance(
        Account storage _account,
        uint256 _interestRate,
        uint256 _blockNumber
    ) internal view returns (uint256) {
        uint256 totalInterest = getTotalInterest(
            _account,
            _interestRate,
            _blockNumber
        );
        return _account.balance.add(totalInterest);
    }

    function updateInterest(
        Account storage _account,
        uint256 _interestRate,
        uint256 _blockNumber
    ) internal {
        _account.interest = getTotalInterest(
            _account,
            _interestRate,
            _blockNumber
        );
        _account.lastInterestBlock = _blockNumber;
    }

    function decreaseBalanceBy(
        Account storage _account,
        uint256 _decrease,
        uint256 _interestRate,
        uint256 _blockNumber
    ) internal {
        uint256 interest = getTotalInterest(_account, _interestRate, _blockNumber);
        if(_decrease <= interest) {
            _account.interest = interest.sub(_decrease);
        } else {
            _account.balance = _account.balance.sub(_decrease.sub(interest));
            _account.interest = 0;
        }

    function increaseBalanceBy(
        Account storage _account,
        uint256 _increase,
        uint256 _interestRate,
        uint256 _blockNumber
    ) internal {
        updateInterest(_account, _interestRate, _blockNumber);
        _account.balance = _account.balance.add(_increase);
    }
}
