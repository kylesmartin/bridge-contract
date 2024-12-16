// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPauseTarget {
  function pause() external;

  function unpause() external;

  function paused() external returns (bool);

  function pauseFn(
    bytes4 fnSig
  ) external;

  function unpauseFn(
    bytes4 fnSig
  ) external;

  function paused(
    bytes4 fnSig
  ) external view returns (bool);
}
