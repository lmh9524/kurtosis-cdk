// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal EIP-1967 transparent upgradeable proxy stack
/// @dev 该实现等价于 OpenZeppelin 4.9 时代的 TransparentUpgradeableProxy 行为，
///      仅保留本项目需要的功能：admin/implementation 管理与 upgradeToAndCall。

/// @notice Interface used by ProxyAdmin to perform upgrades.
interface ITransparentUpgradeableProxy {
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}

/// @dev Minimal transparent proxy implementation following EIP-1967.
contract TransparentUpgradeableProxy is ITransparentUpgradeableProxy {
    // keccak256("eip1967.proxy.implementation") - 1
    bytes32 private constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // keccak256("eip1967.proxy.admin") - 1
    bytes32 private constant _ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    event AdminChanged(address previousAdmin, address newAdmin);
    event Upgraded(address implementation);

    /// @dev Modifier to make a function callable only by the admin.
    modifier ifAdmin() {
        if (msg.sender == _getAdmin()) {
            _;
        } else {
            _fallback();
        }
    }

    constructor(address _logic, address admin_, bytes memory _data) payable {
        require(_logic != address(0), "Proxy: logic is zero");
        require(admin_ != address(0), "Proxy: admin is zero");

        _setAdmin(admin_);
        _setImplementation(_logic);

        if (_data.length > 0) {
            (bool success, bytes memory returndata) = _logic.delegatecall(_data);
            if (!success) {
                assembly {
                    revert(add(returndata, 32), mload(returndata))
                }
            }
        }
    }

    // ========= Admin view =========

    /// @notice Returns the current admin.
    function admin() external ifAdmin returns (address) {
        return _getAdmin();
    }

    /// @notice Returns the current implementation.
    function implementation() external ifAdmin returns (address) {
        return _getImplementation();
    }

    // ========= Admin-only upgrade API =========

    /// @notice Changes the admin of the proxy.
    function changeAdmin(address newAdmin) external ifAdmin {
        require(newAdmin != address(0), "Proxy: new admin is zero");
        emit AdminChanged(_getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /// @notice Upgrades the implementation and optionally calls a function on the new implementation.
    /// @dev 该接口由 ProxyAdmin 调用，用于执行升级。
    function upgradeToAndCall(address newImplementation, bytes memory data)
        external
        payable
        override
        ifAdmin
    {
        _upgradeTo(newImplementation);

        if (data.length > 0) {
            (bool success, bytes memory returndata) = newImplementation.delegatecall{value: msg.value}(data);
            if (!success) {
                assembly {
                    revert(add(returndata, 32), mload(returndata))
                }
            }
        } else {
            require(msg.value == 0, "Proxy: non-zero value with empty data");
        }
    }

    // ========= Fallback to implementation =========

    fallback() external payable virtual {
        _fallback();
    }

    receive() external payable virtual {
        _fallback();
    }

    function _fallback() internal virtual {
        _delegate(_getImplementation());
    }

    function _delegate(address implementation_) internal virtual {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation_, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    // ========= Internal storage helpers =========

    function _getImplementation() internal view returns (address impl) {
        bytes32 slot = _IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    function _setImplementation(address newImplementation) internal {
        require(newImplementation != address(0), "Proxy: impl is zero");
        bytes32 slot = _IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, newImplementation)
        }
        emit Upgraded(newImplementation);
    }

    function _getAdmin() internal view returns (address adm) {
        bytes32 slot = _ADMIN_SLOT;
        assembly {
            adm := sload(slot)
        }
    }

    function _setAdmin(address newAdmin) internal {
        bytes32 slot = _ADMIN_SLOT;
        assembly {
            sstore(slot, newAdmin)
        }
    }
}


