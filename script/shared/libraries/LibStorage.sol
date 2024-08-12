// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library LibStorage {
  function getMappingElementSlotIndex(address key, uint256 mappingSlotIndex) internal pure returns (bytes32 $$) {
    return keccak256(abi.encode(key, mappingSlotIndex));
  }
}
