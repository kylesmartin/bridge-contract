// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ITransparentUpgradeableProxyV2 } from "script/interfaces/ITransparentUpgradeableProxyV2.sol";
import { IBridgeManager } from "@ronin/contracts/interfaces/bridge/IBridgeManager.sol";
import { BasePostCheck } from "script/post-check/BasePostCheck.s.sol";
import { LibArray } from "script/shared/libraries/LibArray.sol";

abstract contract PostCheck_BridgeManager_CRUD_RemoveBridgeOperators is BasePostCheck {
  using LibArray for *;

  /// @dev The seed for generating random values.
  string private seedStr = vm.toString(seed);
  /// @dev The operator to be removed.
  address private op2Remove;
  /// @dev The weight of the operator to be removed.
  uint256 private vw2Remove;
  /// @dev A random address.
  address private any = makeAddr(string.concat("any", seedStr));

  function _validate_BridgeManager_CRUD_removeBridgeOperators() internal {
    address[] memory operators = IBridgeManager(ronBM).getBridgeOperators();
    uint256 idx = _bound(seed, 0, operators.length - 1);

    op2Remove = operators[idx];
    vw2Remove = IBridgeManager(ronBM).getBridgeOperatorWeight(op2Remove);

    validate_RevertWhen_NotSelfCalled_removeBridgeOperators();
    validate_RevertWhen_SelfCalled_TheListHasDuplicate_removeBridgeOperators();
    validate_RevertWhen_SelfCalled_TheListHasNull_removeBridgeOperators();
    validate_RevertWhen_SelfCalled_RemovedOperatorIsNotInTheList_removeBridgeOperators();
    validate_removeBridgeOperators();
  }

  function validate_RevertWhen_NotSelfCalled_removeBridgeOperators() private onPostCheck("validate_RevertWhen_NotSelfCalled_removeBridgeOperators") {
    vm.prank(any);
    vm.expectRevert();
    ITransparentUpgradeableProxyV2(ronBM).functionDelegateCall(abi.encodeCall(IBridgeManager.removeBridgeOperators, (op2Remove.toSingletonArray())));
  }

  function validate_RevertWhen_SelfCalled_TheListHasDuplicate_removeBridgeOperators()
    private
    onPostCheck("validate_RevertWhen_SelfCalled_TheListHasDuplicate_removeBridgeOperators")
  {
    vm.prank(ronBM);
    vm.expectRevert();
    ITransparentUpgradeableProxyV2(ronBM).functionDelegateCall(
      abi.encodeCall(IBridgeManager.removeBridgeOperators, (op2Remove.toSingletonArray().extend(op2Remove.toSingletonArray())))
    );
  }

  function validate_RevertWhen_SelfCalled_TheListHasNull_removeBridgeOperators()
    private
    onPostCheck("validate_RevertWhen_SelfCalled_TheListHasNull_removeBridgeOperators")
  {
    vm.prank(ronBM);
    vm.expectRevert();
    ITransparentUpgradeableProxyV2(ronBM).functionDelegateCall(abi.encodeCall(IBridgeManager.removeBridgeOperators, (address(0).toSingletonArray())));
  }

  function validate_RevertWhen_SelfCalled_RemovedOperatorIsNotInTheList_removeBridgeOperators()
    private
    onPostCheck("validate_RevertWhen_SelfCalled_RemovedOperatorIsNotInTheList_removeBridgeOperators")
  {
    vm.expectRevert();
    vm.prank(ronBM);
    ITransparentUpgradeableProxyV2(ronBM).functionDelegateCall(abi.encodeCall(IBridgeManager.removeBridgeOperators, (any.toSingletonArray())));
  }

  function validate_removeBridgeOperators() private onPostCheck("validate_removeBridgeOperators") {
    uint256 opCount = IBridgeManager(ronBM).totalBridgeOperator();
    uint256 prvTotalWeight = IBridgeManager(ronBM).getTotalWeight();
    uint256 expected = opCount - 1;

    vm.prank(ronBM);
    ITransparentUpgradeableProxyV2(ronBM).functionDelegateCall(abi.encodeCall(IBridgeManager.removeBridgeOperators, (op2Remove.toSingletonArray())));
    uint256 actual = IBridgeManager(ronBM).totalBridgeOperator();

    assertEq(actual, expected, "Bridge operator is not removed");
    assertEq(IBridgeManager(ronBM).getTotalWeight(), prvTotalWeight - vw2Remove, "Bridge operator is not removed");
    assertFalse(IBridgeManager(ronBM).isBridgeOperator(op2Remove), "Bridge operator is not removed");
    assertEq(IBridgeManager(ronBM).getBridgeOperatorWeight(op2Remove), 0, "Bridge operator is not removed");
    // Deprecated
    // assertEq(IBridgeManager(ronBM).getGovernorsOf(op2Remove.toSingletonArray()), address(0).toSingletonArray(), "Bridge operator is not removed");
  }
}
