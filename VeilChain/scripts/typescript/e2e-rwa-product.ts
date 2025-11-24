import { ethers } from 'ethers';
import {
  KYCRegistryUpgradeableV2__factory,
  RWAProductUpgradeable__factory,
} from '../../typechain-types';
import * as fs from 'fs';

/**
 * RWAProductUpgradeable 生命周期 E2E 示例（发行 → 申购 → 派息）
 *
 * 前置条件（在 Kurtosis L2 或本地 devnet 上）：
 * 1. 已部署：
 *    - KYCRegistryUpgradeableV2（通过 Transparent Proxy）
 *    - RWAProductUpgradeable（通过 Transparent Proxy，已初始化 admin / kycRegistry / assetRegistry）
 * 2. investor 地址账户已经持有足够的底层代币（如 USDC），且已在该代币合约上对 RWAProduct Proxy 执行 approve。
 *
 * 环境变量：
 * - ETH_RPC_URL            （可选，默认 http://127.0.0.1:1043）
 * - ADMIN_PRIVATE_KEY      （发行人 / 管理员私钥）
 * - INVESTOR_PRIVATE_KEY   （投资人私钥）
 * - KYC_REGISTRY_PROXY     （KYCRegistryUpgradeableV2 Proxy 地址）
 * - RWA_PRODUCT_PROXY      （RWAProductUpgradeable Proxy 地址）
 * - UNDERLYING_TOKEN       （标的 ERC20 代币地址，例如 MockERC20 或 USDC）
 */

async function main() {
  const rpcUrl = process.env.ETH_RPC_URL || 'http://127.0.0.1:1043';
  const adminPk = process.env.ADMIN_PRIVATE_KEY;
  const investorPk = process.env.INVESTOR_PRIVATE_KEY;
  const kycProxyEnv = process.env.KYC_REGISTRY_PROXY;
  const rwaProxyEnv = process.env.RWA_PRODUCT_PROXY;
  const underlyingToken = process.env.UNDERLYING_TOKEN;

  if (!adminPk || !investorPk) {
    throw new Error('❌ 请设置 ADMIN_PRIVATE_KEY 和 INVESTOR_PRIVATE_KEY 环境变量');
  }
  if (!kycProxyEnv || !rwaProxyEnv || !underlyingToken) {
    throw new Error('❌ 请设置 KYC_REGISTRY_PROXY / RWA_PRODUCT_PROXY / UNDERLYING_TOKEN 环境变量');
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const admin = new ethers.Wallet(adminPk, provider);
  const investor = new ethers.Wallet(investorPk, provider);

  console.log('📡 RPC URL:', rpcUrl);
  console.log('👤 Admin   :', admin.address);
  console.log('👤 Investor:', investor.address);
  console.log('🏦 KYC Proxy     :', kycProxyEnv);
  console.log('🏦 RWAProduct Proxy:', rwaProxyEnv);
  console.log('🪙 Underlying Token:', underlyingToken);

  // 可选：从部署文件中覆盖地址
  try {
    const deployments = JSON.parse(
      fs.readFileSync('deployments/kurtosis/addresses.json', 'utf8')
    );
    if (deployments.contracts?.KYCRegistryProxy?.address) {
      console.log('📁 使用部署文件中的 KYCRegistryProxy 地址');
    }
    if (deployments.contracts?.RWAProductProxy?.address) {
      console.log('📁 使用部署文件中的 RWAProductProxy 地址');
    }
  } catch {
    // 没有部署文件时忽略
  }

  const kycRegistry = KYCRegistryUpgradeableV2__factory.connect(kycProxyEnv, admin);
  const rwaProduct = RWAProductUpgradeable__factory.connect(rwaProxyEnv, admin);

  // 1. 为投资人地址设置 KYC（Approved）
  console.log('\n🧾 1) 设置投资人 KYC 状态...');
  const expiry = Math.floor(Date.now() / 1000) + 365 * 24 * 3600;
  const setKycTx = await kycRegistry.setKYCStatus(
    investor.address,
    1, // Status.Approved
    2, // level
    expiry,
    ethers.id('provider-veil-001')
  );
  console.log('   ⏳ Tx hash:', setKycTx.hash);
  await setKycTx.wait();

  const approved = await kycRegistry.isKYCApproved(investor.address);
  console.log('   ✅ isKYCApproved(investor):', approved);

  // 2. 管理员发行一款产品
  console.log('\n🏦 2) 发行 RWA 产品...');
  const productId = ethers.id('bond-2025-001');
  const totalSupply = ethers.parseUnits('1000000', 18); // 100 万份
  const pricePerShare = ethers.parseUnits('100', 18);   // 每份 100
  const maturityDate = Math.floor(Date.now() / 1000) + 365 * 24 * 3600;
  const interestRateBp = 500; // 5% 年化

  const issueTx = await rwaProduct.issueProduct(
    productId,
    'US Treasury Bond 2025',
    underlyingToken,
    totalSupply,
    pricePerShare,
    maturityDate,
    interestRateBp
  );
  console.log('   ⏳ Issue tx hash:', issueTx.hash);
  await issueTx.wait();

  // 3. 投资人申购（假设已提前 approve && 拥有足够底层 token）
  console.log('\n💳 3) 投资人申购...');
  const investorConnected = rwaProduct.connect(investor);
  const subscribeShares = ethers.parseUnits('1000', 18); // 1000 份

  const subscribeTx = await investorConnected.subscribe(productId, subscribeShares);
  console.log('   ⏳ Subscribe tx hash:', subscribeTx.hash);
  await subscribeTx.wait();

  const holding = await rwaProduct.holdings(productId, investor.address);
  console.log('   ✅ 申购后持有份额:', holding.toString());

  // 4. 管理员派息（例如持有 30 天）
  console.log('\n💰 4) 管理员派息...');
  const daysHeld = 30;
  const investors = [investor.address];

  const interestTx = await rwaProduct.distributeInterest(productId, investors, daysHeld);
  console.log('   ⏳ DistributeInterest tx hash:', interestTx.hash);
  await interestTx.wait();

  console.log('\n✅ RWAProductUpgradeable E2E 示例执行结束（发行 → 申购 → 派息 已完成调用）。');
}

main().catch((error) => {
  console.error('❌ Error in e2e-rwa-product:', error);
  process.exit(1);
});


