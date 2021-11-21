//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;
import "./interfaces/IBank.sol";
import "./interfaces/IPriceOracle.sol";
import "./test/HAKToken.sol";

contract Bank is IBank {
    mapping(address => uint256) private accountBalanceHAK;
    mapping(address => uint256) private accountBalanceETH;
    mapping(address => uint256) private accountLoanETH;

    mapping(address => uint256) private accountInterestHAK;
    mapping(address => uint256) private accountInterestETH;
    mapping(address => uint256) private accountLoanInterestETH;

    mapping(address => uint256) private accountInterestLastBlockNumberHAK;
    mapping(address => uint256) private accountInterestLastBlockNumberETH;
    mapping(address => uint256) private accountLoanInterestLastBlockNumberETH;

    address private priceOracleAddress;
    IPriceOracle private priceOracle;
    IERC20 private hakToken;
    address private hakTokenAddress;

    address private constant ETH_TOKEN =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor(address _priceOracle, address _hakToken) {
        priceOracleAddress = _priceOracle;
        priceOracle = IPriceOracle(_priceOracle);
        hakTokenAddress = _hakToken;
        hakToken = IERC20(_hakToken);
    }

    function getNewInterest(address accountAddress, address token)
        private
        view
        returns (uint256)
    {
        if (token == hakTokenAddress) {
            uint256 pastBlockCount = block.number -
                accountInterestLastBlockNumberHAK[accountAddress];
            uint256 interest = (accountBalanceHAK[accountAddress] *
                pastBlockCount *
                3) / 10000;
            return interest;
        } else if (token == ETH_TOKEN) {
            uint256 pastBlockCount = block.number -
                accountInterestLastBlockNumberETH[accountAddress];
            uint256 interest = (accountBalanceETH[accountAddress] *
                pastBlockCount *
                3) / 10000;
            return interest;
        } else {
            revert("token not supported");
        }
    }

    function calculateInterest(address accountAddress, address token) private {
        if (token == hakTokenAddress) {
            uint256 interest = getNewInterest(accountAddress, token);
            accountInterestHAK[accountAddress] += interest;
            accountInterestLastBlockNumberHAK[accountAddress] = block.number;
        } else if (token == ETH_TOKEN) {
            uint256 interest = getNewInterest(accountAddress, token);
            accountInterestETH[accountAddress] += interest;
            accountInterestLastBlockNumberETH[accountAddress] = block.number;
        } else {
            revert("token not supported");
        }
    }

    function deposit(address token, uint256 amount)
        external
        payable
        override
        returns (bool)
    {
        require(amount > 0);
        if (token == hakTokenAddress) {
            bool approved = hakToken.transferFrom(
                msg.sender,
                address(this),
                amount
            );
            require(approved, "check your allowance");
            calculateInterest(msg.sender, token);

            accountBalanceHAK[msg.sender] += amount;
            emit Deposit(msg.sender, token, amount);
            return true;
        } else if (token == ETH_TOKEN) {
            require(msg.value == amount);
            calculateInterest(msg.sender, token);

            accountBalanceETH[msg.sender] += amount;
            emit Deposit(msg.sender, token, amount);
            return true;
        }
        revert("token not supported");
    }

    function withdraw(address token, uint256 amount)
        external
        override
        returns (uint256)
    {
        require(amount >= 0);
        if (token == hakTokenAddress) {
            calculateInterest(msg.sender, token);
            uint256 accountTotal = accountBalanceHAK[msg.sender] +
                accountInterestHAK[msg.sender];

            require(accountTotal > 0, "no balance");
            require(accountTotal >= amount, "amount exceeds balance");
            if (amount == 0) {
                amount = accountTotal;
            }

            require(hakToken.balanceOf(address(this)) >= amount);
            bool successful = hakToken.transfer(msg.sender, amount);
            require(successful);
            if (accountInterestHAK[msg.sender] >= amount) {
                accountInterestHAK[msg.sender] -= amount;
            } else {
                accountBalanceHAK[msg.sender] -= (amount -
                    accountInterestHAK[msg.sender]);
                accountInterestHAK[msg.sender] = 0;
            }
            emit Withdraw(msg.sender, token, amount);

            return amount;
        } else if (token == ETH_TOKEN) {
            calculateInterest(msg.sender, token);
            uint256 accountTotal = accountBalanceETH[msg.sender] +
                accountInterestETH[msg.sender];

            require(accountTotal > 0, "no balance");
            require(accountTotal >= amount, "amount exceeds balance");
            if (amount == 0) {
                amount = accountTotal;
            }

            require(address(this).balance >= amount);
            msg.sender.transfer(amount);
            if (accountInterestETH[msg.sender] >= amount) {
                accountInterestETH[msg.sender] -= amount;
            } else {
                accountBalanceETH[msg.sender] -= (amount -
                    accountInterestETH[msg.sender]);
                accountInterestETH[msg.sender] = 0;
            }
            emit Withdraw(msg.sender, token, amount);

            return amount;
        }
        revert("token not supported");
    }

    function borrow(address token, uint256 amount)
        external
        override
        returns (
            uint256
        )
    {
        require(amount >= 0);
        require(token == ETH_TOKEN, "token not supported");
        require(accountBalanceHAK[msg.sender] > 0, "no collateral deposited");

        uint256 pastBlockCount = block.number -
            accountLoanInterestLastBlockNumberETH[msg.sender];
        uint256 newInterest = (accountLoanETH[msg.sender] *
            pastBlockCount *
            5) / 10000;
        accountLoanInterestETH[msg.sender] += newInterest;
        accountLoanInterestLastBlockNumberETH[msg.sender] = block.number;

        if (amount == 0) {
            calculateInterest(msg.sender, hakTokenAddress);
            amount =
                (2 *
                    (accountBalanceHAK[msg.sender] +
                        accountInterestHAK[msg.sender])) /
                3;
            amount -= (accountLoanETH[msg.sender] +
                accountLoanInterestETH[msg.sender]);
        }

        calculateInterest(msg.sender, hakTokenAddress);

        uint256 collateralRatio = ((accountBalanceHAK[msg.sender] +
            accountInterestHAK[msg.sender]) * 10000) /
            (accountLoanETH[msg.sender] +
                accountLoanInterestETH[msg.sender] +
                amount);

        require(
            collateralRatio >= 15000,
            "borrow would exceed collateral ratio"
        );

        accountLoanETH[msg.sender] += amount;
        require(address(this).balance >= amount);
        msg.sender.transfer(amount);

        uint256 newCollateralRatio = getCollateralRatio(
            hakTokenAddress,
            msg.sender
        );
        emit Borrow(msg.sender, token, amount, newCollateralRatio);

        return newCollateralRatio;
    }

    function repay(address token, uint256 amount)
        external
        payable
        override
        returns (uint256)
    {
        require(amount >= 0, "amount is < 0");
        require(token == ETH_TOKEN, "token not supported");

        uint256 pastBlockCount = block.number -
            accountLoanInterestLastBlockNumberETH[msg.sender];
        uint256 interest = (accountLoanETH[msg.sender] * pastBlockCount * 5) /
            10000;
        accountLoanInterestETH[msg.sender] += interest;
        accountLoanInterestLastBlockNumberETH[msg.sender] = block.number;

        if (amount == 0) {
            amount =
                accountLoanETH[msg.sender] +
                accountLoanInterestETH[msg.sender];
        }

        require(accountLoanInterestETH[msg.sender] > 0, "nothing to repay");
        require(msg.value >= amount, "msg.value < amount to repay");

        if (amount <= accountLoanInterestETH[msg.sender]) {
            accountLoanInterestETH[msg.sender] -= amount;
        } else {
            require(
                accountLoanETH[msg.sender] >=
                    (amount - accountLoanInterestETH[msg.sender]),
                "insufficient eth balance in account"
            );
            accountLoanETH[msg.sender] -= (amount -
                accountLoanInterestETH[msg.sender]);
            accountLoanInterestETH[msg.sender] = 0;
        }

        uint256 remainingDebt = accountLoanETH[msg.sender];
        require(
            address(this).balance >= remainingDebt,
            "insufficient eth balance in smart contract"
        );
        msg.sender.transfer(remainingDebt);

        emit Repay(msg.sender, token, remainingDebt);
        return remainingDebt;
    }

    function liquidate(address token, address account)
        external
        payable
        override
        returns (bool)
    {
        require(token == hakTokenAddress, "token not supported");
        require(account != msg.sender, "cannot liquidate own position");
        require(getCollateralRatio(token, account) < 15000, "healty position");

        uint256 pastBlockCount = block.number -
            accountLoanInterestLastBlockNumberETH[account];
        uint256 interest = (accountLoanETH[account] * pastBlockCount * 5) /
            10000;

        require(
            msg.value >= (accountLoanETH[account] + interest),
            "insufficient ETH sent by liquidator"
        );

        uint256 amountOfCollateral = accountBalanceHAK[account] +
            accountInterestHAK[account];
        accountBalanceHAK[msg.sender] += amountOfCollateral;
        accountBalanceHAK[account] = 0;

        uint256 amountSentBack = (msg.value) -
            (accountLoanETH[account] + interest);

        accountLoanETH[account] = 0;
        accountLoanInterestETH[account] = 0;

        bool success = hakToken.transfer(msg.sender, amountOfCollateral);
        require(success, "transaction failed");

        msg.sender.transfer(amountSentBack);

        emit Liquidate(
            msg.sender,
            account,
            token,
            amountOfCollateral,
            amountSentBack
        );
        return true;
    }

    function getCollateralRatio(address token, address account)
        public
        view
        override
        returns (uint256)
    {
        require(token == hakTokenAddress);

        if (accountBalanceHAK[account] == 0) {
            return 0;
        } else if (accountLoanETH[account] == 0) {
            return type(uint256).max;
        } else {
            uint256 newHAKInterest = accountInterestHAK[account] +
                getNewInterest(account, token);

            uint256 hakToEthFactor = priceOracle.getVirtualPrice(
                hakTokenAddress
            ) / 1000000000000000000;

            uint256 collateralRatio = ((accountBalanceHAK[account] +
                newHAKInterest) *
                hakToEthFactor *
                10000) /
                (accountLoanETH[account] + getTotalLoanInterest(account));
            return collateralRatio;
        }
    }

    function getTotalLoanInterest(address account)
        private
        view
        returns (uint256)
    {
        uint256 pastBlockCount = block.number -
            accountLoanInterestLastBlockNumberETH[account];
        uint256 newInterest = (accountLoanETH[account] * pastBlockCount * 5) /
            10000;
        uint256 totalLoanInterest = accountLoanInterestETH[account] +
            newInterest;
        return totalLoanInterest;
    }

    function getBalance(address token) public view override returns (uint256) {
        if (token == hakTokenAddress) {
            return
                accountBalanceHAK[msg.sender] +
                getNewInterest(msg.sender, token);
        } else if (token == ETH_TOKEN) {
            return
                accountBalanceETH[msg.sender] +
                getNewInterest(msg.sender, token);
        } else {
            revert("unsupported token");
        }
    }
}