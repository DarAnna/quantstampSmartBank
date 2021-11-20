//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.0;

import "@openzeppelin/contracts@3.4.0/token/ERC20/ERC20.sol";


interface IPriceOracle {
    /**
     * The purpose of this function is to retrieve the price of the given token
     * in ETH. For example if the price of a HAK token is worth 0.5 ETH, then
     * this function will return 500000000000000000 (5e17) because ETH has 18
     * decimals. Note that this price is not fixed and might change at any moment,
     * according to the demand and supply on the open market.
     * @param token - the ERC20 token for which you want to get the price in ETH.
     * @return - the price in ETH of the given token at that moment in time.
     */
    function getVirtualPrice(address token) view external returns (uint256);
}

interface IBank {
    struct Account { // Note that token values have an 18 decimal precision
        uint256 deposit;           // accumulated deposits made into the account
        uint256 interest;          // accumulated interest
        uint256 lastInterestBlock; // block at which interest was last computed
    }
    // Event emitted when a user makes a deposit
    event Deposit(
        address indexed _from, // account of user who deposited
        address indexed token, // token that was deposited
        uint256 amount // amount of token that was deposited
    );
    // Event emitted when a user makes a withdrawal
    event Withdraw(
        address indexed _from, // account of user who withdrew funds
        address indexed token, // token that was withdrawn
        uint256 amount // amount of token that was withdrawn
    );
    // Event emitted when a user borrows funds
    event Borrow(
        address indexed _from, // account who borrowed the funds
        address indexed token, // token that was borrowed
        uint256 amount, // amount of token that was borrowed
        uint256 newCollateralRatio // collateral ratio for the account, after the borrow
    );
    // Event emitted when a user (partially) repays a loan
    event Repay(
        address indexed _from, // accout which repaid the loan
        address indexed token, // token that was borrowed and repaid
        uint256 remainingDebt // amount that still remains to be paid (including interest)
    );
    // Event emitted when a loan is liquidated
    event Liquidate(
        address indexed liquidator, // account which performs the liquidation
        address indexed accountLiquidated, // account which is liquidated
        address indexed collateralToken, // token which was used as collateral
    // for the loan (not the token borrowed)
        uint256 amountOfCollateral, // amount of collateral token which is sent to the liquidator
        uint256 amountSentBack // amount of borrowed token that is sent back to the
    // liquidator in case the amount that the liquidator
    // sent for liquidation was higher than the debt of the liquidated account
    );
    /**
     * The purpose of this function is to allow end-users to deposit a given
     * token amount into their bank account.
     * @param token - the address of the token to deposit. If this address is
     *                set to 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE then
     *                the token to deposit is ETH.
     * @param amount - the amount of the given token to deposit.
     * @return - true if the deposit was successful, otherwise revert.
     */
    function deposit(address token, uint256 amount) payable external returns (bool);

    /**
     * The purpose of this function is to allow end-users to withdraw a given
     * token amount from their bank account. Upon withdrawal, the user must
     * automatically receive a 3% interest rate per 100 blocks on their deposit.
     * @param token - the address of the token to withdraw. If this address is
     *                set to 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE then
     *                the token to withdraw is ETH.
     * @param amount - the amount of the given token to withdraw. If this param
     *                 is set to 0, then the maximum amount available in the
     *                 caller's account should be withdrawn.
     * @return - the amount that was withdrawn plus interest upon success,
     *           otherwise revert.
     */
    function withdraw(address token, uint256 amount) external returns (uint256);

    /**
     * The purpose of this function is to allow users to borrow funds by using their
     * deposited funds as collateral. The minimum ratio of deposited funds over
     * borrowed funds must not be less than 150%.
     * @param token - the address of the token to borrow. This address must be
     *                set to 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, otherwise
     *                the transaction must revert.
     * @param amount - the amount to borrow. If this amount is set to zero (0),
     *                 then the amount borrowed should be the maximum allowed,
     *                 while respecting the collateral ratio of 150%.
     * @return - the current collateral ratio.
     */
    function borrow(address token, uint256 amount) external returns (uint256);

    /**
     * The purpose of this function is to allow users to repay their loans.
     * Loans can be repaid partially or entirely. When replaying a loan, an
     * interest payment is also required. The interest on a loan is equal to
     * 5% of the amount lent per 100 blocks. If the loan is repaid earlier,
     * or later then the interest should be proportional to the number of
     * blocks that the amount was borrowed for.
     * @param token - the address of the token to repay. If this address is
     *                set to 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE then
     *                the token is ETH.
     * @param amount - the amount to repay including the interest.
     * @return - the amount still left to pay for this loan, excluding interest.
     */
    function repay(address token, uint256 amount) payable external returns (uint256);

    /**
     * The purpose of this function is to allow so called keepers to collect bad
     * debt, that is in case the collateral ratio goes below 150% for any loan.
     * @param token - the address of the token used as collateral for the loan.
     * @param account - the account that took out the loan that is now undercollateralized.
     * @return - true if the liquidation was successful, otherwise revert.
     */
    function liquidate(address token, address account) payable external returns (bool);

    /**
     * The purpose of this function is to return the collateral ratio for any account.
     * The collateral ratio is computed as the value deposited divided by the value
     * borrowed. However, if no value is borrowed then the function should return
     * uint256 MAX_INT = type(uint256).max
     * @param token - the address of the deposited token used a collateral for the loan.
     * @param account - the account that took out the loan.
     * @return - the value of the collateral ratio with 2 percentage decimals, e.g. 1% = 100.
     *           If the account has no deposits for the given token then return zero (0).
     *           If the account has deposited token, but has not borrowed anything then
     *           return MAX_INT.
     */
    function getCollateralRatio(address token, address account) view external returns (uint256);

    /**
     * The purpose of this function is to return the balance that the caller
     * has in their own account for the given token (including interest).
     * @param token - the address of the token for which the balance is computed.
     * @return - the value of the caller's balance with interest, excluding debts.
     */
    function getBalance(address token) view external returns (uint256);
}




contract Bank is IBank {

    // user address to token address to user Account
    mapping (address => mapping (address => Account)) private balances;

    address public etherium_adress = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address priceOracleContractAddress;
    IPriceOracle priceOracle;
    address HAKTokenContract;

    mapping (address => Loan[]) private loans;

    struct Loan {
        uint256 amount;
        uint256 lastBlock;
        uint256 ownedInterest; // (amount / 10000) * 5 for one block
    }

    constructor(address _priceOracleContract, address _HAKTokenContract) {
        priceOracleContractAddress = _priceOracleContract;
        HAKTokenContract = _HAKTokenContract;
        priceOracle = IPriceOracle(priceOracleContractAddress);
    }

    function deposit(address token, uint256 amount) override payable external checkToken(token) returns (bool) {
        //require(msg.value == amount, "Amount not equal to true value");
        updateDepositInterest(token);
        if(token == HAKTokenContract) {
            ERC20(HAKTokenContract).transferFrom(msg.sender, address(this), amount);
        }
        balances[msg.sender][token].deposit += amount;
        emit Deposit(msg.sender, token, amount);
        return true;
    }

    /*
    iterest is updated every time we call this function
    */
    function updateDepositInterest(address token) internal {
        uint256 numberOfBlocks = block.number - balances[msg.sender][token].lastInterestBlock;
        uint256 interestPerBlock = balances[msg.sender][token].deposit * 3 / 100;
        uint256 delta = interestPerBlock * numberOfBlocks / 100;
        balances[msg.sender][token].lastInterestBlock = block.number;
        balances[msg.sender][token].interest += delta;
    }

    function withdraw(address token, uint256 amount) override checkToken(token) external returns (uint256) {
        require(balances[msg.sender][token].deposit > 0, "no balance");
        updateDepositInterest(token);
        uint256 sum = balances[msg.sender][token].deposit + balances[msg.sender][token].interest;
        require(amount <= sum, "amount exceeds balance");
        if (amount == 0) {
            amount = sum;
        }
        uint256 transferAmount = amount;
        if (amount > balances[msg.sender][token].interest) {
            balances[msg.sender][token].deposit -= amount - balances[msg.sender][token].interest;
            amount = balances[msg.sender][token].interest;
        }
        balances[msg.sender][token].interest -= amount;
        msg.sender.transfer(transferAmount);
        emit Withdraw(msg.sender, token, transferAmount);
        return transferAmount;
    }


    function borrow(address token, uint256 amount) override external returns (uint256) {
        require(token == etherium_adress, "token not supported");
        require(balances[msg.sender][HAKTokenContract].deposit > 0, "no collateral deposited");
        uint256 collateral = this.getCollateralRatio(HAKTokenContract, msg.sender);
        require(collateral >= 150000, "borrow would exceed collateral ratio");
        loans[msg.sender].push(Loan(amount, block.number, 0));
        msg.sender.transfer(amount);
        uint256 newColl = this.getCollateralRatio(HAKTokenContract, msg.sender);
        emit Borrow(msg.sender, token, amount, newColl);
        return newColl;
    }

    function repay(address token, uint256 amount) override payable external returns (uint256) {
        require(token == etherium_adress, "token not supported");
        require(hasLoans(msg.sender), "nothing to repay");
        return 0;
    }

    function hasLoans(address account) view internal returns (bool) {
        uint256 length = loans[account].length;
        if (length == 2**256 - 1) return false;
        if (length == 0) return false;
        uint256 sum = 0;
        for (uint i=0; i<length; i++) {
            sum += loans[account][i].amount;
        }
        if (sum == 0) return false;
        return true;
    }

    function sumOfLoans(address account) view internal returns (uint256) {
        uint256 length = loans[account].length;
        uint256 sum = 0;
        for (uint i=0; i<length; i++) {
            sum += loans[account][i].amount;
            sum += loans[account][i].ownedInterest;
            uint256 blocks = block.number - loans[account][i].lastBlock;
            sum += loans[account][i].amount * blocks * 5/ 10000;
        }
        return sum;
    }

    function liquidate(address token, address account) override payable external returns (bool) {
        require(token == HAKTokenContract, "token not supported");
        require(account != msg.sender, "cannot liquidate own position");
    }


    function getCollateralRatio(address token, address account) override view external returns (uint256) {
        require(token == HAKTokenContract, "token not supported");
        uint256 numberOfBlocks = block.number - balances[msg.sender][token].lastInterestBlock;
        uint256 interestPerBlock = balances[msg.sender][token].deposit * 3 / 100;
        uint256 delta = interestPerBlock * numberOfBlocks / 100;
        uint256 sumOfHAK = balances[account][token].deposit + balances[account][token].interest + delta;
        if(sumOfHAK == 0) {
            return 0;
        }
        if (!hasLoans(account)) {
            return 2**256 - 1;
        }
        return (priceOracle.getVirtualPrice(HAKTokenContract) * sumOfHAK)/(sumOfLoans(account));
    }

    function getBalance(address token) override view external checkToken(token) returns (uint256) {
        uint256 numberOfBlocks = block.number - balances[msg.sender][token].lastInterestBlock;
        uint256 interestPerBlock = balances[msg.sender][token].deposit * 3 / 100;
        uint256 delta = interestPerBlock * numberOfBlocks / 100;
        return balances[msg.sender][token].deposit + balances[msg.sender][token].interest + delta;
    }

    modifier checkToken(address token) {
        require(token == etherium_adress || token == HAKTokenContract,
            "token not supported"
        );
        _;
    }

}