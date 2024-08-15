// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17 <0.9.0;

import { StdCheats } from "forge-std/Test.sol";

import { Assertions } from "./utils/Assertions.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { Utils } from "./utils/Utils.sol";
import { CommonBase } from "forge-std/Base.sol";
import { IBridgeManagerEvents } from "@ronin/contracts/interfaces/bridge/events/IBridgeManagerEvents.sol";

abstract contract Base_Test is Assertions, Utils, StdCheats, IBridgeManagerEvents { }
