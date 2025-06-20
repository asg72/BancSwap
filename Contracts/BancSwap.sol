// BancSwap/
// ├── contracts/
// │   └── Project.sol
// ├── README.md
// └── package.json

// File: BancSwap/contracts/Project.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title BancSwap
 * @dev Decentralized token swap protocol with automated market making
 */
contract Project {
    
    struct Pool {
        address tokenA;
        address tokenB;
        uint256 reserveA;
        uint256 reserveB;
        uint256 totalSupply;
        mapping(address => uint256) liquidityBalance;
    }
    
    mapping(bytes32 => Pool) public pools;
    mapping(address => bool) public supportedTokens;
    
    address public owner;
    uint256 public constant FEE_RATE = 3; // 0.3% fee
    uint256 public constant FEE_DENOMINATOR = 1000;
    
    event PoolCreated(address indexed tokenA, address indexed tokenB, bytes32 poolId);
    event LiquidityAdded(bytes32 indexed poolId, address indexed provider, uint256 amountA, uint256 amountB);
    event TokensSwapped(bytes32 indexed poolId, address indexed user, address tokenIn, uint256 amountIn, uint256 amountOut);
    event LiquidityRemoved(bytes32 indexed poolId, address indexed provider, uint256 amountA, uint256 amountB);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Creates a new liquidity pool for token pair
     * @param tokenA Address of first token
     * @param tokenB Address of second token
     * @param amountA Initial amount of tokenA
     * @param amountB Initial amount of tokenB
     */
    function createPool(
        address tokenA, 
        address tokenB, 
        uint256 amountA, 
        uint256 amountB
    ) external {
        require(tokenA != tokenB, "Identical tokens");
        require(amountA > 0 && amountB > 0, "Invalid amounts");
        require(supportedTokens[tokenA] && supportedTokens[tokenB], "Unsupported tokens");
        
        bytes32 poolId = getPoolId(tokenA, tokenB);
        require(pools[poolId].tokenA == address(0), "Pool exists");
        
        Pool storage pool = pools[poolId];
        pool.tokenA = tokenA;
        pool.tokenB = tokenB;
        pool.reserveA = amountA;
        pool.reserveB = amountB;
        pool.totalSupply = sqrt(amountA * amountB);
        pool.liquidityBalance[msg.sender] = pool.totalSupply;
        
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
        
        emit PoolCreated(tokenA, tokenB, poolId);
    }
    
    /**
     * @dev Swaps tokens using automated market maker formula
     * @param tokenIn Address of input token
     * @param tokenOut Address of output token
     * @param amountIn Amount of input tokens
     * @param minAmountOut Minimum acceptable output amount
     */
    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external {
        require(amountIn > 0, "Invalid input amount");
        bytes32 poolId = getPoolId(tokenIn, tokenOut);
        Pool storage pool = pools[poolId];
        require(pool.tokenA != address(0), "Pool not found");
        
        bool isTokenAInput = (tokenIn == pool.tokenA);
        uint256 reserveIn = isTokenAInput ? pool.reserveA : pool.reserveB;
        uint256 reserveOut = isTokenAInput ? pool.reserveB : pool.reserveA;
        
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE_RATE);
        uint256 amountOut = (amountInWithFee * reserveOut) / 
                           (reserveIn * FEE_DENOMINATOR + amountInWithFee);
        
        require(amountOut >= minAmountOut, "Insufficient output amount");
        require(amountOut < reserveOut, "Insufficient liquidity");
        
        if (isTokenAInput) {
            pool.reserveA += amountIn;
            pool.reserveB -= amountOut;
        } else {
            pool.reserveB += amountIn;
            pool.reserveA -= amountOut;
        }
        
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, amountOut);
        
        emit TokensSwapped(poolId, msg.sender, tokenIn, amountIn, amountOut);
    }
    
    /**
     * @dev Adds liquidity to existing pool
     * @param tokenA Address of first token
     * @param tokenB Address of second token
     * @param amountA Amount of tokenA to add
     * @param amountB Amount of tokenB to add
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) external {
        bytes32 poolId = getPoolId(tokenA, tokenB);
        Pool storage pool = pools[poolId];
        require(pool.tokenA != address(0), "Pool not found");
        
        uint256 liquidityMinted = min(
            (amountA * pool.totalSupply) / pool.reserveA,
            (amountB * pool.totalSupply) / pool.reserveB
        );
        
        require(liquidityMinted > 0, "Insufficient liquidity minted");
        
        pool.reserveA += amountA;
        pool.reserveB += amountB;
        pool.totalSupply += liquidityMinted;
        pool.liquidityBalance[msg.sender] += liquidityMinted;
        
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
        
        emit LiquidityAdded(poolId, msg.sender, amountA, amountB);
    }
    
    /**
     * @dev Removes liquidity from pool
     * @param tokenA Address of first token
     * @param tokenB Address of second token
     * @param liquidity Amount of liquidity tokens to burn
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity
    ) external {
        bytes32 poolId = getPoolId(tokenA, tokenB);
        Pool storage pool = pools[poolId];
        require(pool.liquidityBalance[msg.sender] >= liquidity, "Insufficient liquidity");
        
        uint256 amountA = (liquidity * pool.reserveA) / pool.totalSupply;
        uint256 amountB = (liquidity * pool.reserveB) / pool.totalSupply;
        
        pool.liquidityBalance[msg.sender] -= liquidity;
        pool.totalSupply -= liquidity;
        pool.reserveA -= amountA;
        pool.reserveB -= amountB;
        
        IERC20(tokenA).transfer(msg.sender, amountA);
        IERC20(tokenB).transfer(msg.sender, amountB);
        
        emit LiquidityRemoved(poolId, msg.sender, amountA, amountB);
    }
    
    /**
     * @dev Admin function to add supported tokens
     * @param token Address of token to support
     */
    function addSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = true;
    }
    
    // Helper functions
    function getPoolId(address tokenA, address tokenB) public pure returns (bytes32) {
        return tokenA < tokenB ? 
            keccak256(abi.encodePacked(tokenA, tokenB)) : 
            keccak256(abi.encodePacked(tokenB, tokenA));
    }
    
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
    
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
    
    // View functions
    function getPoolReserves(address tokenA, address tokenB) external view returns (uint256, uint256) {
        bytes32 poolId = getPoolId(tokenA, tokenB);
        Pool storage pool = pools[poolId];
        return (pool.reserveA, pool.reserveB);
    }
    
    function getLiquidityBalance(address tokenA, address tokenB, address user) external view returns (uint256) {
        bytes32 poolId = getPoolId(tokenA, tokenB);
        return pools[poolId].liquidityBalance[user];
    }
}

// File: BancSwap/README.md
/*
# BancSwap

## Project Description

BancSwap is a decentralized automated market maker (AMM) protocol built on Ethereum that enables seamless token swapping and liquidity provision. The protocol implements a constant product formula (x * y = k) to facilitate trades without the need for traditional order books, providing users with instant liquidity and fair pricing mechanisms.

## Project Vision

Our vision is to create a fully decentralized, efficient, and user-friendly token exchange protocol that empowers users to:
- Trade tokens without intermediaries
- Provide liquidity and earn fees
- Access fair market pricing through automated market making
- Participate in a truly decentralized financial ecosystem

BancSwap aims to be the go-to solution for DeFi users seeking reliable, transparent, and cost-effective token swapping services.

## Key Features

- **Automated Market Making**: Uses constant product formula for price discovery
- **Liquidity Pools**: Users can create and contribute to token pair pools
- **Token Swapping**: Instant token exchanges with minimal slippage
- **Liquidity Mining**: Earn fees by providing liquidity to pools
- **Decentralized**: No central authority or intermediaries
- **Gas Efficient**: Optimized smart contracts for lower transaction costs
- **Multi-token Support**: Support for any ERC-20 compliant tokens
- **Fair Fee Structure**: Transparent 0.3% trading fee distributed to liquidity providers

## Future Scope

### Phase 1 - Enhanced Features
- **Governance Token**: Launch native BCS token for protocol governance
- **Yield Farming**: Additional reward mechanisms for liquidity providers
- **Flash Loans**: Enable uncollateralized loans for arbitrage opportunities
- **Price Oracle Integration**: Integrate with external price feeds for better accuracy

### Phase 2 - Cross-chain Expansion
- **Multi-chain Support**: Deploy on Polygon, BSC, and other EVM-compatible chains
- **Cross-chain Bridges**: Enable seamless asset transfers between chains
- **Layer 2 Integration**: Implement on Arbitrum and Optimism for faster, cheaper transactions

### Phase 3 - Advanced DeFi Features
- **Concentrated Liquidity**: Allow LPs to provide liquidity within specific price ranges
- **Perpetual Swaps**: Enable leveraged trading with perpetual contracts
- **Options Trading**: Introduce decentralized options trading platform
- **Insurance Pools**: Protocol insurance for smart contract risks

### Phase 4 - Ecosystem Development
- **Mobile Application**: Native mobile app for iOS and Android
- **Advanced Analytics**: Comprehensive trading and liquidity analytics dashboard
- **API Integration**: RESTful APIs for third-party integrations
- **Developer SDKs**: Tools and libraries for developers building on BancSwap

### Long-term Vision
- Become a leading multi-chain DEX aggregator
- Integrate with emerging blockchain technologies
- Build a comprehensive DeFi ecosystem around BancSwap
- Achieve full community governance and decentralization
*/

// File: BancSwap/package.json
/*
{
  "name": "bancswap",
  "version": "1.0.0",
  "description": "Decentralized token swap protocol with automated market making",
  "main": "contracts/Project.sol",
  "scripts": {
    "compile": "hardhat compile",
    "test": "hardhat test",
    "deploy": "hardhat run scripts/deploy.js",
    "verify": "hardhat verify"
  },
  "keywords": [
    "defi",
    "dex",
    "amm",
    "solidity",
    "ethereum",
    "swap",
    "liquidity"
  ],
  "author": "BancSwap Team",
  "license": "MIT",
  "devDependencies": {
    "@nomiclabs/hardhat-ethers": "^2.2.3",
    "@nomiclabs/hardhat-waffle": "^2.0.6",
    "chai": "^4.3.8",
    "ethereum-waffle": "^4.0.10",
    "ethers": "^5.7.2",
    "hardhat": "^2.17.1"
  },
  "dependencies": {
    "@openzeppelin/contracts": "^4.9.3"
  }
}
*/
