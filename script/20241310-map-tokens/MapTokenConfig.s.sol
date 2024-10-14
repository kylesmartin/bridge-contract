// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IRoninGatewayV3 } from "@ronin/contracts/interfaces/IRoninGatewayV3.sol";

import { Migration } from "script/Migration.s.sol";
import { MapTokenInfo } from "script/libraries/MapTokenInfo.sol";
import { TokenStandard } from "@ronin/contracts/libraries/LibTokenInfo.sol";
import { Contract } from "script/utils/Contract.sol";
import { Network } from "script/utils/Network.sol";

abstract contract MapTokenConfig is Migration {
  uint256 internal constant _DEFAULT_EXPIRY_DURATION = 10 days;

  /* 
    * @dev
    * LUA
    * Decimal: 18
    * Contract Address:
    * Ronin:  0x9f8E937803BEa0C99563E6CCa84111D2bEB782d0
    * Ethereum: 0x88d100432f98956b16b66df56962fd3e5ccd297a
    * Threshold config:
    * minThreshold = 4
    * highTierThreshold = 10,000
    * lockedThreshold = 40,000;
    * dailyWithdrawalLimit = 30,000
    * unlockFeePercentages = 0.001%;
    */
  MapTokenInfo internal _lua = MapTokenInfo({
    roninToken: 0x9f8E937803BEa0C99563E6CCa84111D2bEB782d0,
    mainchainToken: 0x88D100432F98956b16B66Df56962FD3e5cCd297A,
    minThreshold: 4 ether,
    highTierThreshold: 10_000 ether,
    lockedThreshold: 40_000 ether,
    dailyWithdrawalLimit: 30_000 ether,
    unlockFeePercentages: 10, // Max percentage is: 1_000_000
    standard: TokenStandard.ERC20
  });

  /*
    * @dev
    * LUAUSD
    * Token Name: Lumi Finance USD
    * Token Symbol: LUAUSD
    * Decimal: 18
    * Contract Address:
    * Ronin:  0x416F9B0d4660B01b208AA22C092A9a5f22A379C1
    * Ethereum: 0x540dde0739eefaf90d0ca05aca90513ce89e7e79
    * Threshold config:
    * minThreshold = 10
    * highTierThreshold = 50,000
    * lockedThreshold = 200,000;
    * dailyWithdrawalLimit = 100,000
    * unlockFeePercentages = 0.001%;
    */
  MapTokenInfo internal _luaUSD = MapTokenInfo({
    roninToken: 0x416F9B0d4660B01b208AA22C092A9a5f22A379C1,
    mainchainToken: 0x540ddE0739EeFAf90D0Ca05aCa90513Ce89E7e79,
    minThreshold: 10 ether,
    highTierThreshold: 50_000 ether,
    lockedThreshold: 200_000 ether,
    dailyWithdrawalLimit: 100_000 ether,
    unlockFeePercentages: 10, // Max percentage is: 1_000_000
    standard: TokenStandard.ERC20
  });

  /*
    * @dev
    * ANIMA
    * Token Name: Anima
    * Token Symbol: ANIMA
    * Decimal: 18
    * Contract Address:
    * Ronin:  0xF80132FC0A86ADd011BffCe3AedD60A86E3d704D
    * Ethereum: 0xB110caa8128DDCd08C57B3cD0d9Ba3E9fa0eD85A
    * Threshold config:
    * minThreshold = 1200
    * highTierThreshold = 5,000,000
    * lockedThreshold = 20,000,000;
    * dailyWithdrawalLimit = 12,000,000
    * unlockFeePercentages = 0.001%;
    */
  MapTokenInfo internal _anima = MapTokenInfo({
    roninToken: 0xF80132FC0A86ADd011BffCe3AedD60A86E3d704D,
    mainchainToken: 0xB110caa8128DDCd08C57B3cD0d9Ba3E9fa0eD85A,
    minThreshold: 1200 ether,
    highTierThreshold: 5_000_000 ether,
    lockedThreshold: 20_000_000 ether,
    dailyWithdrawalLimit: 12_000_000 ether,
    unlockFeePercentages: 10, // Max percentage is: 1_000_000
    standard: TokenStandard.ERC20
  });

  /*
  * @dev
  * CFDR
  * Token Name: Cambria Founders
  * Token Symbol: CFDR
  * Token Type: ERC-721
  * Contract Address:
  * Ronin:  0x342fcfc16943a930251d15fccdcd95104f9b4e5f
  * Ethereum: 0xe41af8c3f0decf206c3afb9dbf2e7643f349e0b9
  */
  MapTokenInfo internal _cfdr = MapTokenInfo({
    roninToken: 0x342fcFC16943A930251d15fCCdCD95104F9B4E5f,
    mainchainToken: 0xE41Af8c3F0decf206c3AFb9DBf2E7643F349E0b9,
    minThreshold: 0,
    highTierThreshold: 0,
    lockedThreshold: 0,
    dailyWithdrawalLimit: 0,
    unlockFeePercentages: 0,
    standard: TokenStandard.ERC721
  });

  MapTokenInfo[] internal _mapTokens;

  function run() public virtual {
    _mapTokens.push(_lua);
    _mapTokens.push(_luaUSD);
    _mapTokens.push(_anima);
    _mapTokens.push(_cfdr);
  }

  function getMainchainMapData() public view returns (address[] memory targets, uint256[] memory values, bytes[] memory callDatas, uint256[] memory gasAmounts) {
    targets = new address[](1);
    values = new uint256[](1);
    callDatas = new bytes[](1);
    gasAmounts = new uint256[](1);

    // function mapTokensAndThresholds(
    //   address[] calldata _mainchainTokens,
    //   address[] calldata _roninTokens,
    //   TokenStandard[] calldata _standards,
    //   uint256[][4] calldata _thresholds
    // )
    uint256 tokenCount = _mapTokens.length;
    address[] memory roninTokens = new address[](tokenCount);
    address[] memory mainchainTokens = new address[](tokenCount);
    TokenStandard[] memory standards = new TokenStandard[](tokenCount);
    uint256[][4] memory thresholds;
    thresholds[0] = new uint256[](tokenCount);
    thresholds[1] = new uint256[](tokenCount);
    thresholds[2] = new uint256[](tokenCount);
    thresholds[3] = new uint256[](tokenCount);

    for (uint256 i; i < tokenCount; i++) {
      roninTokens[i] = _mapTokens[i].roninToken;
      mainchainTokens[i] = _mapTokens[i].mainchainToken;
      standards[i] = _mapTokens[i].standard;

      thresholds[0][i] = _mapTokens[i].highTierThreshold;
      thresholds[1][i] = _mapTokens[i].lockedThreshold;
      thresholds[2][i] = _mapTokens[i].unlockFeePercentages;
      thresholds[3][i] = _mapTokens[i].dailyWithdrawalLimit;
    }

    targets[0] = vme.getAddress(Network.EthMainnet.key(), Contract.MainchainGatewayV3.key());
    values[0] = 0;
    callDatas[0] = abi.encodeWithSignature(
      "functionDelegateCall(bytes)",
      abi.encodeWithSignature("mapTokensAndThresholds(address[],address[],uint8[],uint256[][4])", mainchainTokens, roninTokens, standards, thresholds)
    );
    gasAmounts[0] = 4_000_000;
  }

  function getRoninMapData() public view returns (address[] memory targets, uint256[] memory values, bytes[] memory callDatas, uint256[] memory gasAmounts) {
    targets = new address[](2);
    values = new uint256[](2);
    callDatas = new bytes[](2);
    gasAmounts = new uint256[](2);

    // function mapTokens(
    //   address[] calldata roninTokens,
    //   address[] calldata mainchainTokens,
    //   uint256[] calldata chainIds,
    //   TokenStandard[] calldata standards
    // )
    uint256 tokenCount = _mapTokens.length;
    address[] memory roninTokens = new address[](tokenCount);
    address[] memory mainchainTokens = new address[](tokenCount);
    uint256[] memory chainIds = new uint256[](tokenCount);
    TokenStandard[] memory standards = new TokenStandard[](tokenCount);

    uint256 companionChainId = config.getNetworkData(config.getCompanionNetwork(network())).chainId;
    for (uint256 i; i < tokenCount; i++) {
      roninTokens[i] = _mapTokens[i].roninToken;
      mainchainTokens[i] = _mapTokens[i].mainchainToken;
      chainIds[i] = companionChainId;
      standards[i] = _mapTokens[i].standard;
    }

    targets[0] = loadContract(Contract.RoninGatewayV3.key());
    values[0] = 0;
    callDatas[0] = abi.encodeWithSignature(
      "functionDelegateCall(bytes)",
      abi.encodeWithSignature("mapTokens(address[],address[],uint256[],uint8[])", roninTokens, mainchainTokens, chainIds, standards)
    );
    gasAmounts[0] = 4_000_000;

    // function setMinimumThresholds(
    //   address[] calldata tokens,
    //   uint256[] calldata thresholds
    // );
    roninTokens = new address[](tokenCount - 1);
    uint256[] memory thresholds = new uint256[](tokenCount - 1);
    uint256 j;

    for (uint256 i; i < tokenCount; i++) {
      if (_mapTokens[i].standard == TokenStandard.ERC721) {
        continue;
      }

      roninTokens[j] = _mapTokens[i].roninToken;
      thresholds[j] = _mapTokens[i].minThreshold;
      j++;
    }
    targets[1] = loadContract(Contract.RoninGatewayV3.key());
    values[1] = 0;
    gasAmounts[1] = 1_000_000;
    callDatas[1] =
      abi.encodeWithSignature("functionDelegateCall(bytes)", abi.encodeWithSignature("setMinimumThresholds(address[],uint256[])", roninTokens, thresholds));
  }
}
