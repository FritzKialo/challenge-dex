// SPDX-License-Identifier: MIT
pragma solidity 0.8.20; //Do not change the solidity version as it negatively impacts submission grading

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DEX {
    /////////////////
    /// Errors //////
    /////////////////

    error DexAlreadyInitialized();
    error TokenTransferFailed();
    error InvalidEthAmount();
    error InvalidTokenAmount();
    error InsufficientTokenBalance(uint256 available, uint256 required);
    error InsufficientTokenAllowance(uint256 available, uint256 required);
    error EthTransferFailed(address to, uint256 amount);
    error InsufficientLiquidity(uint256 available, uint256 required);

    //////////////////////
    /// State Variables //
    //////////////////////

    IERC20 public immutable token;

    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;

    ////////////////
    /// Events /////
    ////////////////

    event EthToTokenSwap(address swapper, uint256 tokenOutput, uint256 ethInput);
    event TokenToEthSwap(address swapper, uint256 tokensInput, uint256 ethOutput);
    event LiquidityProvided(address liquidityProvider, uint256 liquidityMinted, uint256 ethInput, uint256 tokensInput);
    event LiquidityRemoved(
        address liquidityRemover,
        uint256 liquidityWithdrawn,
        uint256 tokensOutput,
        uint256 ethOutput
    );

    ///////////////////
    /// Constructor ///
    ///////////////////

    constructor(address tokenAddr) {
        token = IERC20(tokenAddr);
    }

    ///////////////////
    /// Functions /////
    ///////////////////

    function init(uint256 tokens) public payable returns (uint256 initialLiquidity) {
        if (totalLiquidity != 0) {
            revert DexAlreadyInitialized();
        }

        totalLiquidity = address(this).balance;
        liquidity[msg.sender] = totalLiquidity;

        bool success = token.transferFrom(msg.sender, address(this), tokens);
        if (!success) {
            revert TokenTransferFailed();
        }

        return totalLiquidity;
    }

    function price(uint256 xInput, uint256 xReserves, uint256 yReserves) public pure returns (uint256 yOutput) {
        uint256 xInputWithFee = xInput * 997;
        uint256 numerator = xInputWithFee * yReserves;
        uint256 denominator = (xReserves * 1000) + xInputWithFee;
        return numerator / denominator;
    }

    function getLiquidity(address lp) public view returns (uint256 lpLiquidity) {
        return liquidity[lp];
    }

    function ethToToken() public payable returns (uint256 tokenOutput) {
        if (msg.value == 0) {
            revert InvalidEthAmount();
        }

        uint256 ethReserve = address(this).balance - msg.value;
        uint256 tokenReserve = token.balanceOf(address(this));

        tokenOutput = price(msg.value, ethReserve, tokenReserve);

        bool success = token.transfer(msg.sender, tokenOutput);
        if (!success) {
            revert TokenTransferFailed();
        }

        emit EthToTokenSwap(msg.sender, tokenOutput, msg.value);
        return tokenOutput;
    }

    function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {
        if (tokenInput == 0) {
            revert InvalidTokenAmount();
        }

        uint256 userBalance = token.balanceOf(msg.sender);
        if (userBalance < tokenInput) {
            revert InsufficientTokenBalance(userBalance, tokenInput);
        }

        uint256 allowance = token.allowance(msg.sender, address(this));
        if (allowance < tokenInput) {
            revert InsufficientTokenAllowance(allowance, tokenInput);
        }

        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 ethReserve = address(this).balance;

        ethOutput = price(tokenInput, tokenReserve, ethReserve);

        bool success = token.transferFrom(msg.sender, address(this), tokenInput);
        if (!success) {
            revert TokenTransferFailed();
        }

        (bool sent, ) = msg.sender.call{ value: ethOutput }("");
        if (!sent) {
            revert EthTransferFailed(msg.sender, ethOutput);
        }

        emit TokenToEthSwap(msg.sender, tokenInput, ethOutput);
        return ethOutput;
    }

    function deposit() public payable returns (uint256 tokensDeposited) {
        if (msg.value == 0) {
            revert InvalidEthAmount();
        }

        uint256 ethReserve = address(this).balance - msg.value;
        uint256 tokenReserve = token.balanceOf(address(this));

        tokensDeposited = ((msg.value * tokenReserve) / ethReserve) + 1;

        uint256 userBalance = token.balanceOf(msg.sender);
        if (userBalance < tokensDeposited) {
            revert InsufficientTokenBalance(userBalance, tokensDeposited);
        }

        uint256 allowance = token.allowance(msg.sender, address(this));
        if (allowance < tokensDeposited) {
            revert InsufficientTokenAllowance(allowance, tokensDeposited);
        }

        uint256 liquidityMinted = (msg.value * totalLiquidity) / ethReserve;
        liquidity[msg.sender] += liquidityMinted;
        totalLiquidity += liquidityMinted;

        bool success = token.transferFrom(msg.sender, address(this), tokensDeposited);
        if (!success) {
            revert TokenTransferFailed();
        }

        emit LiquidityProvided(msg.sender, liquidityMinted, msg.value, tokensDeposited);
        return tokensDeposited;
    }

    function withdraw(uint256 amount) public returns (uint256 ethAmount, uint256 tokenAmount) {
        uint256 userLiquidity = liquidity[msg.sender];
        if (userLiquidity < amount) {
            revert InsufficientLiquidity(userLiquidity, amount);
        }

        uint256 ethReserve = address(this).balance;
        uint256 tokenReserve = token.balanceOf(address(this));

        ethAmount = (amount * ethReserve) / totalLiquidity;
        tokenAmount = (amount * tokenReserve) / totalLiquidity;

        liquidity[msg.sender] -= amount;
        totalLiquidity -= amount;

        bool success = token.transfer(msg.sender, tokenAmount);
        if (!success) {
            revert TokenTransferFailed();
        }

        (bool sent, ) = msg.sender.call{ value: ethAmount }("");
        if (!sent) {
            revert EthTransferFailed(msg.sender, ethAmount);
        }

        emit LiquidityRemoved(msg.sender, amount, tokenAmount, ethAmount);
        return (ethAmount, tokenAmount);
    }
}