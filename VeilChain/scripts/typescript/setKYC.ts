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
  let proxyAddress: string;

  // 优先使用环境变量覆盖（兼容不同环境）
  const envAddr =
    process.env.KYC_REGISTRY_PROXY ||
    process.env.KYC_REGISTRY_ADDRESS ||
    process.env.KYC_REGISTRY_ADDR;

  if (envAddr) {
    proxyAddress = envAddr;
    console.log('🔧 Using KYC registry address from env:', proxyAddress);
  } else {
    // 其次尝试从部署文件读取
    try {
      const deployments = JSON.parse(
        fs.readFileSync('deployments/kurtosis/addresses.json', 'utf8')
      );
      proxyAddress = deployments.contracts.KYCRegistryProxy.address;
      console.log('📁 Using KYC registry address from deployments file:', proxyAddress);
    } catch {
      // 如果没有部署文件，使用默认地址（当前 PoC 环境的 Proxy）
      proxyAddress = '0x57f47C1F48b1078608f259B17D11f5ac925e5E04';
      console.warn('⚠️  Using default proxy address:', proxyAddress);
    }
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
  // 兼容 V1/V2：优先通过 getRecord 读取 level / expiry / providerId
  let kycLevel: bigint | undefined;
  let riskLevel: bigint | undefined;
  let expiry: bigint | undefined;

  try {
    const record = await kycRegistry.getRecord(userAddress);
    kycLevel = record.level;
    expiry = record.expiry;
  } catch {
    console.warn('⚠️  getRecord() not available on this KYC contract');
  }
  try {
    riskLevel = await kycRegistry.getRiskLevel(userAddress);
  } catch {
    console.warn('⚠️  getRiskLevel() not available on this KYC contract');
  }
  
  console.log('\n📊 KYC Status:');
  console.log('   Approved:', isApprovedAfter);
  if (kycLevel !== undefined) console.log('   KYC Level:', kycLevel.toString());
  if (riskLevel !== undefined) console.log('   Risk Level:', riskLevel.toString());
  if (expiry !== undefined)
    console.log('   Expiry:', new Date(Number(expiry) * 1000).toISOString());
  
  console.log('\n✅ Script completed successfully!');
}

main().catch((error) => {
  console.error('❌ Error:', error);
  process.exit(1);
});

