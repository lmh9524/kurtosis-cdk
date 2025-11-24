import { ethers } from 'ethers';
import { KYCRegistryUpgradeableV2__factory } from '../../typechain-types';
import * as fs from 'fs';

/**
 * 示例脚本：冻结/解冻账户（V2 新功能）
 * 
 * 使用方法：
 * 1. 设置环境变量 ADMIN_PRIVATE_KEY 和 TARGET_USER
 * 2. 设置环境变量 ACTION=freeze 或 ACTION=unfreeze
 * 3. 运行 npx ts-node scripts/typescript/freezeAccount.ts
 */

async function main() {
  // 读取部署地址
  let proxyAddress: string;
  try {
    const deployments = JSON.parse(
      fs.readFileSync('deployments/kurtosis/addresses.json', 'utf8')
    );
    proxyAddress = deployments.contracts.KYCRegistryProxy.address;
  } catch {
    proxyAddress = '0x57f47C1F48b1078608f259B17D11f5ac925e5E04';
    console.warn('⚠️  Using default proxy address:', proxyAddress);
  }

  // 连接到网络
  const rpcUrl = process.env.ETH_RPC_URL || 'http://127.0.0.1:32824';
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  
  const privateKey = process.env.ADMIN_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error('❌ Please set ADMIN_PRIVATE_KEY environment variable');
  }
  const wallet = new ethers.Wallet(privateKey, provider);
  
  // 目标用户
  const userAddress = process.env.TARGET_USER;
  if (!userAddress) {
    throw new Error('❌ Please set TARGET_USER environment variable');
  }
  
  // 动作
  const action = process.env.ACTION || 'freeze';
  if (action !== 'freeze' && action !== 'unfreeze') {
    throw new Error('❌ ACTION must be "freeze" or "unfreeze"');
  }
  
  console.log('📡 Connecting to RPC:', rpcUrl);
  console.log('👤 Admin address:', wallet.address);
  console.log('🎯 Target user:', userAddress);
  console.log('🔧 Action:', action);
  
  // 创建合约实例
  const kycRegistry = KYCRegistryUpgradeableV2__factory.connect(
    proxyAddress,
    wallet
  );
  
  // 检查当前状态
  console.log('\n🔍 Checking current status...');
  const isFrozenBefore = await kycRegistry.isFrozen(userAddress);
  const isApprovedBefore = await kycRegistry.isKYCApproved(userAddress);
  const isVerifiedBefore = await kycRegistry.isVerified(userAddress);
  
  console.log('   Frozen:', isFrozenBefore);
  console.log('   Approved:', isApprovedBefore);
  console.log('   Verified:', isVerifiedBefore);
  
  // 执行动作
  console.log(`\n🚀 Executing ${action}...`);
  let tx;
  if (action === 'freeze') {
    tx = await kycRegistry.freezeAccount(userAddress);
  } else {
    tx = await kycRegistry.unfreezeAccount(userAddress);
  }
  
  console.log('⏳ Waiting for transaction:', tx.hash);
  const receipt = await tx.wait();
  console.log('✅ Transaction confirmed in block:', receipt?.blockNumber);
  
  // 验证结果
  console.log('\n🔍 Checking status after action...');
  const isFrozenAfter = await kycRegistry.isFrozen(userAddress);
  const isApprovedAfter = await kycRegistry.isKYCApproved(userAddress);
  const isVerifiedAfter = await kycRegistry.isVerified(userAddress);
  
  console.log('   Frozen:', isFrozenAfter);
  console.log('   Approved:', isApprovedAfter);
  console.log('   Verified:', isVerifiedAfter);
  
  // 解析事件
  if (receipt) {
    const events = receipt.logs
      .map(log => {
        try {
          return kycRegistry.interface.parseLog({
            topics: log.topics as string[],
            data: log.data
          });
        } catch {
          return null;
        }
      })
      .filter(e => e !== null);
    
    console.log('\n📋 Events emitted:');
    events.forEach(event => {
      if (event) {
        console.log(`   - ${event.name}`);
        console.log(`     Account: ${event.args.account}`);
        console.log(`     Admin: ${event.args.admin}`);
      }
    });
  }
  
  console.log('\n✅ Script completed successfully!');
}

main().catch((error) => {
  console.error('❌ Error:', error);
  process.exit(1);
});

