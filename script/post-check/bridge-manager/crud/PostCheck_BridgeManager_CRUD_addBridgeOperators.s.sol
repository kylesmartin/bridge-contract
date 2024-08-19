// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ITransparentUpgradeableProxyV2 } from "script/interfaces/ITransparentUpgradeableProxyV2.sol";
import { IBridgeManager } from "@ronin/contracts/interfaces/bridge/IBridgeManager.sol";
import { BasePostCheck } from "script/post-check/BasePostCheck.s.sol";
import { LibArray } from "script/shared/libraries/LibArray.sol";

/**
 * @title PostCheck_BridgeManager_CRUD_AddBridgeOperators
 * @dev This contract contains post-check functions for adding bridge operators in the BridgeManager contract.
 */
abstract contract PostCheck_BridgeManager_CRUD_AddBridgeOperators is BasePostCheck {
  using LibArray for *;

  /// @dev The vote weight of the operator.
  uint256 private vw = 100;
  /// @dev The seed for generating random values.
  string private seedStr = vm.toString(seed);
  /// @dev The operator to be added.
  address private any = makeAddr(string.concat("any", seedStr));
  /// @dev The operator to be added.
  address private op = makeAddr(string.concat("op-", seedStr));
  /// @dev The governor of the operator.
  address private gv = makeAddr(string.concat("gv-", seedStr));

  function _validate_BridgeManager_CRUD_addBridgeOperators() internal {
    validate_RevertWhen_NotSelfCalled_addBridgeOperators();
    validate_RevertWhen_SelfCalled_TheListHasDuplicate_addBridgeOperators();
    validate_RevertWhen_SelfCalled_InputArrayLengthMismatch_addBridgeOperators();
    validate_RevertWhen_SelfCalled_ContainsNullVoteWeight_addBridgeOperators();
    validate_addBridgeOperators();
  }

  /**
   * @dev Validates that the function `addBridgeOperators` reverts when it is not self-called.
   */
  function validate_RevertWhen_NotSelfCalled_addBridgeOperators() private onPostCheck("validate_RevertWhen_NotSelfCalled_addBridgeOperators") {
    vm.expectRevert();
    vm.prank(any);
    IBridgeManager(ronBM).addBridgeOperators(vw.toSingletonArray().toUint96sUnsafe(), op.toSingletonArray(), gv.toSingletonArray());
  }

  /**
   * @dev Validates that the function `addBridgeOperators` reverts when the list of operators contains duplicates.
   */
  function validate_RevertWhen_SelfCalled_TheListHasDuplicate_addBridgeOperators()
    private
    onPostCheck("validate_RevertWhen_SelfCalled_TheListHasDuplicate_addBridgeOperators")
  {
    vm.expectRevert();
    vm.prank(ronBM);
    ITransparentUpgradeableProxyV2(ronBM).functionDelegateCall(
      abi.encodeCall(IBridgeManager.addBridgeOperators, (vw.toSingletonArray().toUint96sUnsafe(), op.toSingletonArray(), op.toSingletonArray()))
    );

    vm.expectRevert();
    vm.prank(ronBM);
    ITransparentUpgradeableProxyV2(ronBM).functionDelegateCall(
      abi.encodeCall(IBridgeManager.addBridgeOperators, (vw.toSingletonArray().toUint96sUnsafe(), gv.toSingletonArray(), gv.toSingletonArray()))
    );

    vm.expectRevert();
    vm.prank(ronBM);
    ITransparentUpgradeableProxyV2(ronBM).functionDelegateCall(
      abi.encodeCall(
        IBridgeManager.addBridgeOperators,
        (vw.toSingletonArray().toUint96sUnsafe(), gv.toSingletonArray().extend(op.toSingletonArray()), op.toSingletonArray().extend(gv.toSingletonArray()))
      )
    );
  }

  /**
   * @dev Validates that the function `addBridgeOperators` reverts when the input array lengths mismatch.
   */
  function validate_RevertWhen_SelfCalled_InputArrayLengthMismatch_addBridgeOperators()
    private
    onPostCheck("validate_RevertWhen_SelfCalled_InputArrayLengthMismatch_addBridgeOperators")
  {
    vm.prank(ronBM);
    vm.expectRevert();
    ITransparentUpgradeableProxyV2(ronBM).functionDelegateCall(
      abi.encodeCall(
        IBridgeManager.addBridgeOperators, (vw.toSingletonArray().toUint96sUnsafe(), gv.toSingletonArray(), op.toSingletonArray().extend(gv.toSingletonArray()))
      )
    );
  }

  /**
   * @dev Validates that the function `addBridgeOperators` reverts when the input array contains a null vote weight.
   */
  function validate_RevertWhen_SelfCalled_ContainsNullVoteWeight_addBridgeOperators()
    private
    onPostCheck("validate_RevertWhen_SelfCalled_ContainsNullVoteWeight_addBridgeOperators")
  {
    vm.prank(ronBM);
    vm.expectRevert();
    ITransparentUpgradeableProxyV2(ronBM).functionDelegateCall(
      abi.encodeCall(
        IBridgeManager.addBridgeOperators,
        (uint256(0).toSingletonArray().toUint96sUnsafe(), gv.toSingletonArray(), op.toSingletonArray().extend(gv.toSingletonArray()))
      )
    );
  }

  /**
   * @dev Validates that the function `addBridgeOperators`.
   */
  function validate_addBridgeOperators() private onPostCheck("validate_addBridgeOperators") {
    uint256 prvTotalWeight = IBridgeManager(ronBM).getTotalWeight();
    uint256 prvOpCount = IBridgeManager(ronBM).getBridgeOperators().length;

    vm.prank(ronBM);
    ITransparentUpgradeableProxyV2(ronBM).functionDelegateCall(
      abi.encodeCall(IBridgeManager.addBridgeOperators, (vw.toSingletonArray().toUint96sUnsafe(), gv.toSingletonArray(), op.toSingletonArray()))
    );

    assertTrue(IBridgeManager(ronBM).isBridgeOperator(op), "isBridgeOperator(op) == false");
    assertEq(IBridgeManager(ronBM).getTotalWeight(), prvTotalWeight + vw, "getTotalWeight() != prvTotalWeight + vw");
    assertEq(IBridgeManager(ronBM).getBridgeOperators().length, prvOpCount + 1, "getBridgeOperators().length != prvOpCount + 1");

    // Deprecated
    // assertEq(IBridgeManager(ronBM).getGovernorsOf(op.toSingletonArray())[0], gv, "getGovernorsOf(op)[0] != gv");
    // Deprecated
    // assertEq(IBridgeManager(ronBM).getBridgeOperatorOf(gv.toSingletonArray())[0], op, "getBridgeOperatorOf(gv)[0] != op");
  }
}
