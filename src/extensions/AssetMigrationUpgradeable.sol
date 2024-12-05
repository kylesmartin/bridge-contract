// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IWETH } from "src/interfaces/IWETH.sol";
import { ErrLengthMismatch, ErrEmptyArray } from "src/utils/CommonErrors.sol";

abstract contract AssetMigrationUpgradeable is Initializable {
  using SafeERC20 for IERC20;

  /// @dev Error when the storage location is null
  error ErrInvalidStorageLocation();
  /// @dev Error when the caller is not authorized
  error ErrUnauthorizedCaller(address expected, address caller);

  /// @dev The native token indicator address
  address internal constant _NATIVE_TOKEN_INDICATOR = address(0);

  /// @custom:storage-location erc7201:ronin.bridge.AssetMigration
  struct AssetMigrationStorage {
    IWETH _wnt;
    // Migrator address
    address _addr;
    // Pending migrator address
    address _pendingAddr;
  }

  /// @dev Emitted when a new migrator is set.
  event NewMigrator(address indexed by, address indexed migrator);
  /// @dev Emitted when the wrapped native token is set.
  event WrappedNativeTokenSet(address indexed by, address indexed wnt);
  /// @dev Emitted when the migrator transfer process is started.
  event MigratorTransferStarted(address indexed migrator, address indexed newMigrator);

  /**
   * @dev Modifier to check if the caller is the migrator.
   */
  modifier onlyMigrator() {
    _requireMigrator();
    _;
  }

  /**
   * @dev Returns the wrapped native token.
   * - For `RoninGatewayV3`, it MUST return the WRON token.
   * - For `MainchainGatewayV3`, it MUST return the WETH token.
   */
  function _getWrappedNativeToken() internal view returns (IWETH) {
    return _getAssetMigration()._wnt;
  }

  /**
   * @dev Initializes the neccessary data.
   */
  function __AssetMigration_init(address wnt, address migrator) internal onlyInitializing {
    __AssetMigration_init_unchained(wnt, migrator);
  }

  /**
   * @dev Initializes the neccessary data.
   */
  function __AssetMigration_init_unchained(address wnt, address migrator) internal onlyInitializing {
    _setMigrator(migrator);
    _setWrappedNativeToken(wnt);
  }

  /**
   * @dev Migrates the given tokens to the specified addresses.
   *
   * When the token is the native (i.e RON or ETH), it will be wrapped (i.e WRON, WETH).
   *
   * Requirements:
   * - The caller must be the migrator.
   * - The length of the arrays must be the same.
   * - The length of the arrays must not be zero.
   */
  function adminMigrate(address[] calldata tos, IERC20[] calldata tokens, uint256[] calldata amounts) external onlyMigrator {
    uint256 length = tos.length;

    require(length != 0, ErrEmptyArray());
    require(length == tokens.length && tokens.length == amounts.length, ErrLengthMismatch(msg.sig));

    IERC20 token;

    for (uint256 i; i < length; ++i) {
      token = tokens[i];

      if (address(token) == address(_NATIVE_TOKEN_INDICATOR)) {
        token = _wrap(amounts[i]);
      }

      token.safeTransfer(tos[i], amounts[i]);
    }
  }

  /**
   * @dev Renounces the migrator role.
   */
  function renounceMigrator() external onlyMigrator {
    _setMigrator(address(0));
  }

  /**
   * @dev Starts the process to change the migrator.
   * Replaces the pending migrator address if there is one.
   *
   * Setting `newMigrator` to the zero address is allowed. This will cancel the pending migrator.
   */
  function changeMigrator(
    address newMigrator
  ) external onlyMigrator {
    _getAssetMigration()._pendingAddr = newMigrator;

    emit MigratorTransferStarted(msg.sender, newMigrator);
  }

  /**
   * @dev Accepts the migrator role.
   */
  function acceptMigrator() external {
    require(_getAssetMigration()._pendingAddr == msg.sender, ErrUnauthorizedCaller(_getAssetMigration()._pendingAddr, msg.sender));

    _setMigrator(msg.sender);
  }

  /**
   * @dev Returns the pending migrator address.
   */
  function getPendingMigrator() external view returns (address) {
    return _getAssetMigration()._pendingAddr;
  }

  /**
   * @dev Returns the pointer of the AssetMigrationStorage struct.
   */
  function _getAssetMigration() internal pure returns (AssetMigrationStorage storage $) {
    bytes32 loc = _$$AssetMigrationLocation();
    require(loc != 0, ErrInvalidStorageLocation());

    assembly ("memory-safe") {
      $.slot := loc
    }
  }

  /**
   * @dev Returns the custom storage location of the AssetMigrationStorage struct.
   */
  function _$$AssetMigrationLocation() internal pure virtual returns (bytes32 storageLoc) {
    // value is equal to keccak256(abi.encode(uint256(keccak256("ronin.bridge.AssetMigration")) - 1)) &
    // ~bytes32(uint256(0xff))
    storageLoc = 0xbfb7c7cbd9f93146fbbf37acaa2236698ffc013cbf87c0b4f57505d22ae7c200;
  }

  /**
   * @dev Converts the native token to its wrapped version.
   */
  function _wrap(
    uint256 amount
  ) internal returns (IERC20) {
    IWETH wrappedToken = _getWrappedNativeToken();
    wrappedToken.deposit{ value: amount }();

    return IERC20(address(wrappedToken));
  }

  /**
   * @dev Sets the migrator address.
   * Delete any pending migrator address.
   */
  function _setMigrator(
    address addr
  ) internal {
    _getAssetMigration()._addr = addr;
    delete _getAssetMigration()._pendingAddr;

    emit NewMigrator(msg.sender, addr);
  }

  /**
   * @dev Sets the wrapped native token.
   */
  function _setWrappedNativeToken(
    address wnt
  ) internal {
    _getAssetMigration()._wnt = IWETH(wnt);

    emit WrappedNativeTokenSet(msg.sender, wnt);
  }

  /**
   * @dev Throws if the caller is not the migrator.
   */
  function _requireMigrator() internal view {
    require(_getAssetMigration()._addr != msg.sender, ErrUnauthorizedCaller(_getAssetMigration()._addr, msg.sender));
  }
}
