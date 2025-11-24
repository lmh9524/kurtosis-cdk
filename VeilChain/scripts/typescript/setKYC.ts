import { ethers } from 'ethers';
import { KYCRegistryUpgradeableV2__factory } from '../../typechain-types';
import * as fs from 'fs';

/**
 * 示例脚本：使用 TypeChain 生成的强类型 SDK 设置 KYC 状态
 * 
 * 使用方法：
 * 1. 设置环境变量 ADMIN_PRIVATE_KEY
 * 2. 运行 npm run typechain:all （生成 SDK）
 * 3. 运行 npx ts-node scripts/typescript/setKYC.ts
 */

async function main() {
  // 读取部署地址（如果存在）
  let proxyAddress: string;
  try {
    const deployments = JSON.parse(
      fs.readFileSync('deployments/kurtosis/addresses.json', 'utf8')
    );
    proxyAddress = deployments.contracts.KYCRegistryProxy.address;
  } catch {
    // 如果没有部署文件，使用默认地址
    proxyAddress = '0x57f47C1F48b1078608f259B17D11f5ac925e5E04';
    console.warn('⚠️  Using default proxy address:', proxyAddress);
  }

  // 连接到 Kurtosis L2（从 foundry.toml 读取）
  const rpcUrl = process.env.ETH_RPC_URL || 'http://127.0.0.1:32824';
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  
  // 使用私钥创建钱包
  const privateKey = process.env.ADMIN_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error('❌ Please set ADMIN_PRIVATE_KEY environment variable');
  }
  const wallet = new ethers.Wallet(privateKey, provider);
  
  console.log('📡 Connecting to RPC:', rpcUrl);
  console.log('👤 Admin address:', wallet.address);
  
  // 使用 TypeChain 生成的工厂创建强类型合约实例
  const kycRegistry = KYCRegistryUpgradeableV2__factory.connect(
    proxyAddress,
    wallet
  );
  
  // 目标用户地址
  const userAddress = process.env.TARGET_USER || '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
  
  console.log('🔍 Checking KYC status before...');
  const isApprovedBefore = await kycRegistry.isKYCApproved(userAddress);
  console.log('   Before:', isApprovedBefore);
  
  // 设置 KYC 状态（强类型，IDE 会自动补全）
  console.log('📝 Setting KYC status...');
  const tx = await kycRegistry.setKYCStatus(
    userAddress,
    2, // Status.Approved (枚举值 2，对应 enum Status { None, Pending, Approved, ... })
    2, // kycLevel: 2
    Math.floor(Date.now() / 1000) + 365 * 24 * 3600, // 1 年后过期
    ethers.id('provider-veil-001') // kycProviderId
  );
  
  console.log('⏳ Waiting for transaction:', tx.hash);
  const receipt = await tx.wait();
  console.log('✅ Transaction confirmed in block:', receipt?.blockNumber);
  
  // 验证结果
  console.log('🔍 Checking KYC status after...');
  const isApprovedAfter = await kycRegistry.isKYCApproved(userAddress);
  const kycLevel = await kycRegistry.getKYCLevel(userAddress);
  const riskLevel = await kycRegistry.getRiskLevel(userAddress);
  const expiry = await kycRegistry.getExpiry(userAddress);
  const isVerified = await kycRegistry.isVerified(userAddress);
  
  console.log('\n📊 KYC Status:');
  console.log('   Approved:', isApprovedAfter);
  console.log('   Verified:', isVerified);
  console.log('   KYC Level:', kycLevel);
  console.log('   Risk Level:', riskLevel);
  console.log('   Expiry:', new Date(Number(expiry) * 1000).toISOString());
  
  console.log('\n✅ Script completed successfully!');
}

main().catch((error) => {
  console.error('❌ Error:', error);
  process.exit(1);
});

