// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17 <0.9.0;

import { console2 } from "forge-std/console2.sol";
import { StdStyle } from "forge-std/StdStyle.sol";

import { LibArrayUtils } from "@ronin/test/helpers/LibArrayUtils.t.sol";

import "@ronin/contracts/utils/CommonErrors.sol";
import { IBridgeManager } from "@ronin/contracts/interfaces/bridge/IBridgeManager.sol";

import { BridgeManager_Unit_Concrete_Test } from "../BridgeManager.t.sol";

event BridgeOperatorsAdded(bool[] statuses, uint96[] voteWeights, address[] governors, address[] bridgeOperators);

contract Add_Unit_Concrete_Test is BridgeManager_Unit_Concrete_Test {
  function setUp() public virtual override {
    BridgeManager_Unit_Concrete_Test.setUp();
  }

  function test_RevertWhen_NotSelfCall() external {
    // Prepare data
    (address[] memory addingOperators, address[] memory addingGovernors, uint96[] memory addingWeights) = _generateNewOperators();

    // Run the test.
    vm.expectRevert();
    address(_bridgeManager).call(
      abi.encodeWithSignature(
        "functionDelegateCall(bytes)",
        abi.encodeWithSignature("addBridgeOperators(uint96[],address[],address[])", addingWeights, addingGovernors, addingOperators)
      )
    );
  }

  function test_RevertWhen_ThreeInputArrayLengthMismatch() external {
    // Prepare data
    (address[] memory addingOperators, address[] memory addingGovernors, uint96[] memory addingWeights) = _generateNewOperators();

    uint length = addingOperators.length;

    assembly {
      mstore(addingOperators, add(length, 1))
    }
    vm.expectRevert(abi.encodeWithSelector(ErrLengthMismatch.selector, IBridgeManager.addBridgeOperators.selector));
    vm.prank(address(_bridgeManager));
    address(_bridgeManager).call(
      abi.encodeWithSignature(
        "functionDelegateCall(bytes)",
        abi.encodeWithSignature("addBridgeOperators(uint96[],address[],address[])", addingWeights, addingGovernors, addingOperators)
      )
    );

    assembly {
      mstore(addingOperators, length)
      mstore(addingGovernors, add(length, 1))
    }
    vm.expectRevert(abi.encodeWithSelector(ErrLengthMismatch.selector, IBridgeManager.addBridgeOperators.selector));
    vm.prank(address(_bridgeManager));
    address(_bridgeManager).call(
      abi.encodeWithSignature(
        "functionDelegateCall(bytes)",
        abi.encodeWithSignature("addBridgeOperators(uint96[],address[],address[])", addingWeights, addingGovernors, addingOperators)
      )
    );

    assembly {
      mstore(addingGovernors, length)
      mstore(addingWeights, add(length, 1))
    }
    vm.expectRevert(abi.encodeWithSelector(ErrLengthMismatch.selector, IBridgeManager.addBridgeOperators.selector));
    vm.prank(address(_bridgeManager));
    address(_bridgeManager).call(
      abi.encodeWithSignature(
        "functionDelegateCall(bytes)",
        abi.encodeWithSignature("addBridgeOperators(uint96[],address[],address[])", addingWeights, addingGovernors, addingOperators)
      )
    );
  }

  function test_RevertWhen_VoteWeightIsZero() external {
    // Prepare data
    (address[] memory addingOperators, address[] memory addingGovernors, uint96[] memory addingWeights) = _generateNewOperators();

    addingWeights[0] = 0;
    vm.expectRevert(abi.encodeWithSelector(ErrInvalidVoteWeight.selector, IBridgeManager.addBridgeOperators.selector));
    vm.prank(address(_bridgeManager));
    address(_bridgeManager).call(
      abi.encodeWithSignature(
        "functionDelegateCall(bytes)",
        abi.encodeWithSignature("addBridgeOperators(uint96[],address[],address[])", addingWeights, addingGovernors, addingOperators)
      )
    );
  }

  function test_RevertWhen_BridgeOperatorAddressIsZero() external {
    // Prepare data
    (address[] memory addingOperators, address[] memory addingGovernors, uint96[] memory addingWeights) = _generateNewOperators();

    addingOperators[0] = address(0);
    vm.expectRevert(abi.encodeWithSelector(ErrZeroAddress.selector, IBridgeManager.addBridgeOperators.selector));
    vm.prank(address(_bridgeManager));
    address(_bridgeManager).call(
      abi.encodeWithSignature(
        "functionDelegateCall(bytes)",
        abi.encodeWithSignature("addBridgeOperators(uint96[],address[],address[])", addingWeights, addingGovernors, addingOperators)
      )
    );
  }

  function test_RevertWhen_GovernorAddressIsZero() external {
    // Prepare data
    (address[] memory addingOperators, address[] memory addingGovernors, uint96[] memory addingWeights) = _generateNewOperators();

    addingGovernors[0] = address(0);
    vm.expectRevert(abi.encodeWithSelector(ErrZeroAddress.selector, IBridgeManager.addBridgeOperators.selector));
    vm.prank(address(_bridgeManager));
    address(_bridgeManager).call(
      abi.encodeWithSignature(
        "functionDelegateCall(bytes)",
        abi.encodeWithSignature("addBridgeOperators(uint96[],address[],address[])", addingWeights, addingGovernors, addingOperators)
      )
    );
  }

  function test_AddOperators_DuplicatedGovernor() external assertStateNotChange {
    (address[] memory addingOperators, address[] memory addingGovernors, uint96[] memory addingWeights) = _generateNewOperators();

    addingGovernors[0] = _governors[0];

    bool[] memory expectedAddeds = new bool[](1);
    expectedAddeds[0] = false;
    vm.expectEmit(true, false, false, false);
    emit BridgeOperatorsAdded(expectedAddeds, new uint96[](0), new address[](0), new address[](0));

    vm.prank(address(_bridgeManager));
    (bool success,) = address(_bridgeManager).call(
      abi.encodeWithSignature(
        "functionDelegateCall(bytes)",
        abi.encodeWithSignature("addBridgeOperators(uint96[],address[],address[])", addingWeights, addingGovernors, addingOperators)
      )
    );
    require(success, "BridgeManagerUtils: addBridgeOperators failed");
  }

  function test_AddOperators_DuplicatedBridgeOperator() external assertStateNotChange {
    (address[] memory addingOperators, address[] memory addingGovernors, uint96[] memory addingWeights) = _generateNewOperators();

    addingOperators[0] = _bridgeOperators[0];

    bool[] memory expectedAddeds = new bool[](1);
    expectedAddeds[0] = false;
    vm.expectEmit(true, false, false, false);
    emit BridgeOperatorsAdded(expectedAddeds, new uint96[](0), new address[](0), new address[](0));

    vm.prank(address(_bridgeManager));
    (bool success,) = address(_bridgeManager).call(
      abi.encodeWithSignature(
        "functionDelegateCall(bytes)",
        abi.encodeWithSignature("addBridgeOperators(uint96[],address[],address[])", addingWeights, addingGovernors, addingOperators)
      )
    );
    require(success, "BridgeManagerUtils: addBridgeOperators failed");
  }

  function test_AddOperators_DuplicatedGovernorWithExistedBridgeOperator() external assertStateNotChange {
    (address[] memory addingOperators, address[] memory addingGovernors, uint96[] memory addingWeights) = _generateNewOperators();

    addingGovernors[0] = _bridgeOperators[0];

    bool[] memory expectedAddeds = new bool[](1);
    expectedAddeds[0] = false;
    vm.expectEmit(true, false, false, false);
    emit BridgeOperatorsAdded(expectedAddeds, new uint96[](0), new address[](0), new address[](0));

    vm.prank(address(_bridgeManager));
    (bool success,) = address(_bridgeManager).call(
      abi.encodeWithSignature(
        "functionDelegateCall(bytes)",
        abi.encodeWithSignature("addBridgeOperators(uint96[],address[],address[])", addingWeights, addingGovernors, addingOperators)
      )
    );
    require(success, "BridgeManagerUtils: addBridgeOperators failed");
  }

  function test_AddOperators_DuplicatedBridgeOperatorWithExistedGovernor() external assertStateNotChange {
    (address[] memory addingOperators, address[] memory addingGovernors, uint96[] memory addingWeights) = _generateNewOperators();

    addingOperators[0] = _governors[0];

    bool[] memory expectedAddeds = new bool[](1);
    expectedAddeds[0] = false;
    vm.expectEmit(true, false, false, false);
    emit BridgeOperatorsAdded(expectedAddeds, new uint96[](0), new address[](0), new address[](0));

    vm.prank(address(_bridgeManager));
    (bool success,) = address(_bridgeManager).call(
      abi.encodeWithSignature(
        "functionDelegateCall(bytes)",
        abi.encodeWithSignature("addBridgeOperators(uint96[],address[],address[])", addingWeights, addingGovernors, addingOperators)
      )
    );
    require(success, "BridgeManagerUtils: addBridgeOperators failed");
  }

  function test_AddOperators_AllInfoIsValid() external {
    // Get before test state
    (address[] memory beforeBridgeOperators, address[] memory beforeGovernors, uint96[] memory beforeVoteWeights) = _getBridgeMembers();
    (address[] memory addingOperators, address[] memory addingGovernors, uint96[] memory addingWeights) = _generateNewOperators();

    bool[] memory expectedAddeds = new bool[](1);
    expectedAddeds[0] = true;
    vm.expectEmit(true, false, false, false);
    emit BridgeOperatorsAdded(expectedAddeds, new uint96[](0), new address[](0), new address[](0));

    vm.prank(address(_bridgeManager));
    (bool success,) = address(_bridgeManager).call(
      abi.encodeWithSignature(
        "functionDelegateCall(bytes)",
        abi.encodeWithSignature("addBridgeOperators(uint96[],address[],address[])", addingWeights, addingGovernors, addingOperators)
      )
    );
    require(success, "BridgeManagerUtils: addBridgeOperators failed");
    vm.stopPrank();

    // Compare after and before state
    (address[] memory afterBridgeOperators, address[] memory afterGovernors, uint96[] memory afterVoteWeights) = _getBridgeMembers();
    _totalWeight += addingWeights[0];

    address[] memory expectingOperators = LibArrayUtils.concat(beforeBridgeOperators, addingOperators);
    address[] memory expectingGovernors = LibArrayUtils.concat(beforeGovernors, addingGovernors);
    uint96[] memory expectingWeights = LibArrayUtils.concat(beforeVoteWeights, addingWeights);

    _assertBridgeMembers({
      comparingOperators: afterBridgeOperators,
      comparingGovernors: afterGovernors,
      comparingWeights: afterVoteWeights,
      expectingOperators: expectingOperators,
      expectingGovernors: expectingGovernors,
      expectingWeights: expectingWeights
    });
    assertEq(_bridgeManager.getTotalWeight(), _totalWeight);
  }
}
