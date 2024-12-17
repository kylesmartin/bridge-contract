// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { TokenStandard } from "src/libraries/LibTokenInfo.sol";

interface IPauseTarget {
  function pause() external;

  function unpause() external;

  function paused() external returns (bool);

  function restrict(bytes4 fnSig, TokenStandard standard) external;
}
