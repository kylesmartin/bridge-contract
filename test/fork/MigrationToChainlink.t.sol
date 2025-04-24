// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { MainchainGatewayV3 } from "@ronin/contracts/mainchain/MainchainGatewayV3.sol";
import { RoninGatewayV3 } from "@ronin/contracts/ronin/gateway/RoninGatewayV3.sol";

library CCIP {
  struct EVMTokenAmount {
    address token; // token address on the local chain.
    uint256 amount; // Amount of tokens.
  }

  // If extraArgs is empty bytes, the default is 200k gas limit.
  struct EVM2AnyMessage {
    bytes receiver; // abi.encode(receiver address) for dest EVM chains.
    bytes data; // Data payload.
    EVMTokenAmount[] tokenAmounts; // Token transfers.
    address feeToken; // Address of feeToken. address(0) means you will send msg.value.
    bytes extraArgs; // Populate this with _argsToBytes(EVMExtraArgsV2).
  }

  struct ReleaseOrMintInV1 {
    bytes originalSender; //          The original sender of the tx on the source chain
    uint64 remoteChainSelector; // ─╮ The chain ID of the source chain
    address receiver; // ───────────╯ The recipient of the tokens on the destination chain.
    uint256 amount; //                The amount of tokens to release or mint, denominated in the source token's decimals
    address localToken; //            The address on this chain of the token to release or mint
    /// @dev WARNING: sourcePoolAddress should be checked prior to any processing of funds. Make sure it matches the
    /// expected pool address for the given remoteChainSelector.
    bytes sourcePoolAddress; //       The address of the source pool, abi encoded in the case of EVM chains
    bytes sourcePoolData; //          The data received from the source pool to process the release or mint
    /// @dev WARNING: offchainTokenData is untrusted data.
    bytes offchainTokenData; //       The offchain data to process the release or mint
  }

  struct ReleaseOrMintOutV1 {
    // The number of tokens released or minted on the destination chain, denominated in the local token's decimals.
    // This value is expected to be equal to the ReleaseOrMintInV1.amount in the case where the source and destination
    // chain have the same number of decimals.
    uint256 destinationAmount;
  }
}

interface IMintable {
  function mint(address to, uint256 amount) external;
}

interface IERC20 {
  function approve(address spender, uint256 amount) external returns (bool);
  function balanceOf(
    address account
  ) external view returns (uint256);
  function symbol() external view returns (string memory);
  function decimals() external view returns (uint8);
}

interface IGateway {
  function initializeV4(
    address migrator,
    address newEmergencyPauser,
    address[] memory tokens,
    address[] memory recipients,
    uint64[] memory remoteChainSelectors
  ) external;
  function initializeV5(
    address migrator,
    address newEmergencyPauser,
    address[] memory tokens,
    address[] memory recipients,
    uint64[] memory remoteChainSelectors
  ) external;
  function migrateERC20(address[] calldata tokens, uint256[] calldata amounts) external;
}

interface ITransparentUpgradeableProxy {
  function upgradeTo(
    address newImplementation
  ) external;
}

interface ITokenPool {
  function getToken() external view returns (address);
  function getRemotePools(
    uint64 remoteChainSelector
  ) external view returns (bytes[] memory);
  function releaseOrMint(
    CCIP.ReleaseOrMintInV1 calldata releaseOrMintIn
  ) external returns (CCIP.ReleaseOrMintOutV1 memory);
}

interface IRouter {
  function ccipSend(uint64 destinationChainSelector, CCIP.EVM2AnyMessage memory message) external payable returns (bytes32);
}

contract MigrationToChainlink is Test {
  uint256 private ethereumFork;
  uint256 private roninFork;
  address private user;

  struct TokenPoolInfo {
    address poolAddress;
    uint64 remoteChainSelector;
    string tokenSymbol;
  }

  TokenPoolInfo[] private ethereumPools;
  TokenPoolInfo[] private roninPools;

  bytes32 constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

  address private constant ROUTER_ETH = 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
  address private constant ROUTER_RONIN = 0x46527571D5D1B68eE7Eb60B18A32e6C60DcEAf99;

  address private constant OFF_RAMP_ETH = 0x9a3Ed7007809CfD666999e439076B4Ce4120528D;
  address private constant OFF_RAMP_RONIN = 0x320A10449556388503Fd71D74A16AB52e0BD1dEb;

  address private constant BRIDGE_PROXY_ETH = 0x64192819Ac13Ef72bF6b5AE239AC672B43a9AF08;
  address private constant BRIDGE_PROXY_RONIN = 0x0CF8fF40a508bdBc39fBe1Bb679dCBa64E65C7Df;

  uint64 private constant RONIN_CHAIN_SELECTOR = 6916147374840168594;
  uint64 private constant ETHEREUM_CHAIN_SELECTOR = 5009297550715157269;

  function setUp() public {
    string memory ethRpcUrl = vm.envOr("ETHEREUM_RPC_URL", string(""));
    string memory roninRpcUrl = vm.envOr("RONIN_RPC_URL", string(""));

    if (bytes(ethRpcUrl).length == 0 || bytes(roninRpcUrl).length == 0) {
      vm.skip(true);
    }

    ethereumFork = vm.createFork(ethRpcUrl);
    roninFork = vm.createFork(roninRpcUrl);
    user = vm.randomAddress();

    // Initialize Ethereum pools
    ethereumPools.push(TokenPoolInfo(0xf33341f2CE329B5DbCa7F9a0986Cff40d050440a, 0, "AXS"));
    ethereumPools.push(TokenPoolInfo(0x5882D12bbf902ee88d5FCF8793113ae85fFe97b1, 0, "APRS"));
    ethereumPools.push(TokenPoolInfo(0xe26D9c68cF6d284367C5e90EC834C6Ec0051f73C, 0, "PIXEL"));
    // ethereumPools.push(TokenPoolInfo(0xD27F88501e62D0BDc70B20d6ed06d8E0fF8c3812, 0, "LUA")); TODO: BURNMINT COUNTERPART ON RONIN NEEDS MINTER ROLE
    // ethereumPools.push(TokenPoolInfo(0x5686CCb55ee86BEB1e8A1Cf7C769930f3A5E521c, 0, "LUAUSD")); TODO: BURNMINT COUNTERPART ON RONIN NEEDS MINTER ROLE
    ethereumPools.push(TokenPoolInfo(0x799A356069Ca6D91BBE5d0407De625A969874aE4, 0, "YGG"));
    ethereumPools.push(TokenPoolInfo(0xB18eE11849a805651aC5D456034FD6352cfF635d, 0, "BANANA"));
    ethereumPools.push(TokenPoolInfo(0xc2e3A3C18ccb634622B57fF119a1C8C7f12e8C0c, RONIN_CHAIN_SELECTOR, "USDC"));
    ethereumPools.push(TokenPoolInfo(0x011Ef1fe26D20077A59F38e9Ad155b166AD87D40, RONIN_CHAIN_SELECTOR, "WETH"));
    ethereumPools.push(TokenPoolInfo(0xF6698064776D521b0AFE469F30C40B39B4875b93, RONIN_CHAIN_SELECTOR, "WBTC"));

    // Initialize Ronin pools
    roninPools.push(TokenPoolInfo(0xD27F88501e62D0BDc70B20d6ed06d8E0fF8c3812, 0, "ANIMA"));
    // roninPools.push(TokenPoolInfo(0x5686CCb55ee86BEB1e8A1Cf7C769930f3A5E521c, 0, "SLP")); TODO: BURNMINT COUNTERPART ON ETH NEEDS MINTER ROLE
  }

  function testRoninLiquidityMigration() public {
    // Upgrade the implementation of the Ronin bridge proxy & migrate liquidity to lock release pools
    // Initiate transfers from Ethereum to Ronin & confirm that tokens can properly unlock Ronin
    _upgradeAndMigrateLiquidity(roninFork, BRIDGE_PROXY_RONIN, roninPools);
    _initiateTransfers(1 ether, ethereumFork, ETHEREUM_CHAIN_SELECTOR, ROUTER_ETH, roninFork, RONIN_CHAIN_SELECTOR, roninPools);
    _unlockOnDestination(roninFork, OFF_RAMP_RONIN, ETHEREUM_CHAIN_SELECTOR, roninPools);
  }

  function testEthereumLiquidityMigration() public {
    // Upgrade the implementation of the Ethereum bridge proxy & migrate liquidity to lock release pools
    // Initiate transfers from Ronin to Ethereum & confirm that tokens can properly unlock on Ethereum
    _upgradeAndMigrateLiquidity(ethereumFork, BRIDGE_PROXY_ETH, ethereumPools);
    _initiateTransfers(50 ether, roninFork, RONIN_CHAIN_SELECTOR, ROUTER_RONIN, ethereumFork, ETHEREUM_CHAIN_SELECTOR, ethereumPools);
    _unlockOnDestination(ethereumFork, OFF_RAMP_ETH, RONIN_CHAIN_SELECTOR, ethereumPools);
  }

  function _upgradeAndMigrateLiquidity(uint256 forkId, address proxyAddress, TokenPoolInfo[] storage pools) private {
    vm.selectFork(forkId);
    address implAddress = forkId == ethereumFork ? address(new MainchainGatewayV3()) : address(new RoninGatewayV3());

    ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(proxyAddress);

    address[] memory tokens = new address[](pools.length);
    address[] memory recipients = new address[](pools.length);
    uint64[] memory remoteChainSelectors = new uint64[](pools.length);
    uint256[] memory amounts = new uint256[](pools.length);
    uint256[] memory initialPoolBalance = new uint256[](pools.length);

    for (uint256 i = 0; i < pools.length; i++) {
      TokenPoolInfo memory poolInfo = pools[i];
      tokens[i] = ITokenPool(poolInfo.poolAddress).getToken();
      assertEq(poolInfo.tokenSymbol, IERC20(tokens[i]).symbol(), "Token symbol does not match expected");
      recipients[i] = poolInfo.poolAddress;
      remoteChainSelectors[i] = poolInfo.remoteChainSelector;
      amounts[i] = IERC20(tokens[i]).balanceOf(address(proxy)); // We will transfer the whole balance in this test
      initialPoolBalance[i] = IERC20(tokens[i]).balanceOf(poolInfo.poolAddress);
    }

    // Impersonate admin to perform upgrade
    bytes32 raw = vm.load(address(proxy), ADMIN_SLOT);
    address adminAddress = address(uint160(uint256(raw)));
    vm.startPrank(adminAddress);
    proxy.upgradeTo(implAddress);
    vm.stopPrank();

    // We can replace with actual addresses if need be
    address migrator = vm.randomAddress();
    address newEmergencyPauser = vm.randomAddress();

    // Initialize the new implementation
    IGateway gatewayViaProxy = IGateway(address(proxy));
    if (forkId == ethereumFork) {
      gatewayViaProxy.initializeV5(migrator, newEmergencyPauser, tokens, recipients, remoteChainSelectors);
    } else {
      gatewayViaProxy.initializeV4(migrator, newEmergencyPauser, tokens, recipients, remoteChainSelectors);
    }

    // Migrate liquidity to the token pools
    vm.startPrank(migrator);
    gatewayViaProxy.migrateERC20(tokens, amounts);
    vm.stopPrank();

    // Check pool balances
    for (uint256 i = 0; i < pools.length; i++) {
      TokenPoolInfo memory poolInfo = pools[i];
      uint256 diff = IERC20(tokens[i]).balanceOf(poolInfo.poolAddress) - initialPoolBalance[i];
      assertEq(amounts[i], diff, "Transfer amount does not match diff in pool balance");
    }
  }

  function _initiateTransfers(
    uint256 feePerSend,
    uint256 burnMintChainFork,
    uint64 burnMintChainSelector,
    address routerOnBurnMintChain,
    uint256 lockReleaseChainFork,
    uint64 lockReleaseChainSelector,
    TokenPoolInfo[] storage lockReleasePools
  ) private {
    vm.selectFork(burnMintChainFork);
    vm.deal(user, feePerSend * lockReleasePools.length);

    for (uint256 i = 0; i < lockReleasePools.length; i++) {
      _initiateSingleTransfer(
        lockReleasePools[i], feePerSend, burnMintChainFork, burnMintChainSelector, routerOnBurnMintChain, lockReleaseChainFork, lockReleaseChainSelector
      );
    }
  }

  function _initiateSingleTransfer(
    TokenPoolInfo memory poolInfo,
    uint256 feePerSend,
    uint256 burnMintChainFork,
    uint64 burnMintChainSelector,
    address routerOnBurnMintChain,
    uint256 lockReleaseChainFork,
    uint64 lockReleaseChainSelector
  ) private {
    vm.selectFork(lockReleaseChainFork);
    bytes[] memory remotePools = ITokenPool(poolInfo.poolAddress).getRemotePools(burnMintChainSelector);
    assertEq(1, remotePools.length, "Expected 1 remote pool");

    vm.selectFork(burnMintChainFork);
    address burnMintPool = _bytesToAddress(remotePools[0]);
    address burnMintToken = ITokenPool(burnMintPool).getToken();
    assertEq(poolInfo.tokenSymbol, IERC20(burnMintToken).symbol(), "Token symbol does not match expected");

    uint256 transferAmount = 100;
    vm.startPrank(burnMintPool);
    IMintable(burnMintToken).mint(user, transferAmount);
    vm.stopPrank();

    vm.startPrank(user);
    IERC20(burnMintToken).approve(routerOnBurnMintChain, transferAmount);

    CCIP.EVMTokenAmount[] memory tokenAmounts = new CCIP.EVMTokenAmount[](1);
    tokenAmounts[0] = CCIP.EVMTokenAmount(burnMintToken, transferAmount);

    CCIP.EVM2AnyMessage memory message;
    message.receiver = abi.encode(user);
    message.data = "";
    message.tokenAmounts = tokenAmounts;
    message.feeToken = address(0);
    message.extraArgs = "";

    IRouter(routerOnBurnMintChain).ccipSend{ value: feePerSend }(lockReleaseChainSelector, message);
    vm.stopPrank();
  }

  function _unlockOnDestination(uint256 fork, address offRampAddress, uint64 sourceChainSelector, TokenPoolInfo[] storage lockReleasePools) private {
    vm.selectFork(fork);
    vm.startPrank(offRampAddress);
    for (uint256 i = 0; i < lockReleasePools.length; i++) {
      TokenPoolInfo memory poolInfo = lockReleasePools[i];
      bytes[] memory remotePools = ITokenPool(poolInfo.poolAddress).getRemotePools(sourceChainSelector);
      assertEq(1, remotePools.length, "Expected 1 remote pool");
      address localToken = ITokenPool(poolInfo.poolAddress).getToken();
      assertEq(poolInfo.tokenSymbol, IERC20(localToken).symbol(), "Token symbol does not match expected");

      // Can't test USDC this way because it requires offchain attestations
      // TODO: We could check if the error returned is expected
      if (keccak256(abi.encodePacked(poolInfo.tokenSymbol)) == keccak256(abi.encodePacked("USDC"))) {
        continue;
      }

      ITokenPool(poolInfo.poolAddress).releaseOrMint(
        CCIP.ReleaseOrMintInV1(
          abi.encode(user),
          sourceChainSelector,
          user,
          100, // TODO: Update to test different capacities?
          localToken,
          remotePools[0],
          "",
          ""
        )
      );
      assertEq(100, IERC20(localToken).balanceOf(user), "User balance does not match expected");
    }
    vm.stopPrank();
  }

  function _bytesToAddress(
    bytes memory b
  ) private pure returns (address addr) {
    assertEq(32, b.length, "Invalid bytes length");
    assembly {
      addr := mload(add(b, 32))
    }
  }
}
