// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LibSharedAddress } from "@fdk/libraries/LibSharedAddress.sol";
import { IGeneralConfigExtended } from "script/interfaces/IGeneralConfigExtended.sol";
import { TNetwork } from "@fdk/types/Types.sol";
import { INetworkConfig } from "@fdk/interfaces/configs/INetworkConfig.sol";

library LibCompanionNetwork {
  IGeneralConfigExtended private constant config = IGeneralConfigExtended(LibSharedAddress.CONFIG);

  function companionChainId() internal view returns (uint256 chainId) {
    (chainId,) = companionNetworkData();
  }

  function companionChainId(TNetwork network) internal view returns (uint256 chainId) {
    (chainId,) = companionNetworkData(network);
  }

  function companionNetwork() internal view returns (TNetwork network) {
    (, network) = companionNetworkData();
  }

  function companionNetwork(TNetwork network) internal view returns (TNetwork companionTNetwork) {
    (, companionTNetwork) = companionNetworkData(network);
  }

  function companionNetworkData() internal view returns (uint256, TNetwork) {
    return companionNetworkData(config.getCurrentNetwork());
  }

  function companionNetworkData(TNetwork network) internal view returns (uint256 chainId, TNetwork companionTNetwork) {
    companionTNetwork = config.getCompanionNetwork(network);
    INetworkConfig.NetworkData memory dt = config.getNetworkData(companionTNetwork);
    chainId = dt.chainId;
  }
}
