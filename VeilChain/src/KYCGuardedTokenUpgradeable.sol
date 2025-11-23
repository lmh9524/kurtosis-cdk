// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IAccessController.sol";
import "./interfaces/ILimitController.sol";

/// @title KYCGuardedTokenUpgradeable
/// @notice Upgradeable ERC20 token whose mint/transfer are gated by an external AccessController.
/// @dev Uses TransparentUpgradeableProxy pattern with ProxyAdmin.
contract KYCGuardedTokenUpgradeable is 
    Initializable,
    ERC20Upgradeable, 
    AccessControlUpgradeable, 
    PausableUpgradeable 
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IAccessController public accessController;
    /// @notice Optional limit controller for per-address quota enforcement.
    ILimitController public limitController;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract (replaces constructor for upgradeable pattern).
    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    /// @param admin_ The address to be granted all admin roles.
    /// @param accessController_ The AccessController contract address.
    function initialize(
        string memory name_,
        string memory symbol_,
        address admin_,
        address accessController_
    ) public initializer {
        require(admin_ != address(0), "KYCGuardedToken: admin is zero");
        require(accessController_ != address(0), "KYCGuardedToken: controller is zero");

        __ERC20_init(name_, symbol_);
        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);

        accessController = IAccessController(accessController_);
    }

    /// @notice Update AccessController (e.g. if upgraded).
    function setAccessController(address newController) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newController != address(0), "KYCGuardedToken: controller is zero");
        accessController = IAccessController(newController);
    }

    /// @notice Set or clear the optional LimitController.
    /// @dev Passing the zero address disables limit checks.
    function setLimitController(address newController) external onlyRole(DEFAULT_ADMIN_ROLE) {
        limitController = ILimitController(newController);
    }

    /// @notice Mint tokens to a recipient, checking AccessController.canMint.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @inheritdoc ERC20Upgradeable
    function _update(address from, address to, uint256 value) internal override {
        if (paused()) {
            revert("KYCGuardedToken: paused");
        }

        if (from == address(0)) {
            // Mint
            require(accessController.canMint(to), "KYCGuardedToken: mint not allowed");
        } else if (to != address(0)) {
            // Transfer
            require(
                accessController.canTransfer(from, to),
                "KYCGuardedToken: transfer not allowed"
            );

            // Optional quota check on outbound transfers.
            if (address(limitController) != address(0) && value > 0) {
                limitController.checkAndUpdateOutflow(from, value);
            }
        }

        super._update(from, to, value);
    }

    // --- Pause control ---

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @dev Storage gap for future upgrades (48 slots reserved).
    uint256[48] private __gap;
}

