#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "部署测试 ERC20 合约到 L2"
echo "=========================================="

# 推断 Foundry 项目根目录 = 脚本所在目录的上一级（VeilChain）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 基本环境变量（使用你之前验证 L1/L2 的管理员账户与 RPC）
export ADMIN_KEY="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
export ADMIN_ADDR="0xE34aaF64b29273B7D567FCFc40544c014EEe9970"
export ETH_RPC_URL="http://127.0.0.1:32782"   # L2 RPC
export L1_RPC_URL="http://127.0.0.1:32773"    # L1 RPC
export PRIVATE_KEY="$ADMIN_KEY"

cd "$PROJECT_ROOT"

echo "1️⃣ 创建 Foundry 项目..."
if [ ! -d "test-erc20" ]; then
  forge init test-erc20 --no-git
fi
cd test-erc20

echo "2️⃣ 安装 OpenZeppelin..."
if [ ! -d "lib/openzeppelin-contracts" ]; then
  forge install OpenZeppelin/openzeppelin-contracts
fi

echo "3️⃣ 写入 ERC20 合约 TestToken.sol..."
mkdir -p src
cat > src/TestToken.sol << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TestToken is ERC20, Ownable {
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _mint(msg.sender, initialSupply * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
EOF

echo "4️⃣ 写入 foundry.toml..."
cat > foundry.toml << 'EOF'
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
remappings = [
  "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/"
]

[rpc_endpoints]
l2 = "${ETH_RPC_URL}"
l1 = "${L1_RPC_URL}"
EOF

echo "5️⃣ 写入部署脚本 script/Deploy.s.sol..."
mkdir -p script
cat > script/Deploy.s.sol << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TestToken.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        TestToken token = new TestToken(
            "Test Token",
            "TEST",
            1000000  // 1,000,000 tokens
        );

        console.log("TestToken deployed at:", address(token));
        console.log("Total supply:", token.totalSupply());
        console.log("Deployer balance:", token.balanceOf(msg.sender));

        vm.stopBroadcast();
    }
}
EOF

echo "6️⃣ 编译合约..."
forge build

echo "7️⃣ 部署到 L2..."
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url "$ETH_RPC_URL" \
  --broadcast \
  --legacy

echo ""
echo "=========================================="
echo "✅ 部署完成！"
echo "=========================================="
echo "请在上方输出中查找 'TestToken deployed at: 0x...' 作为合约地址。"
