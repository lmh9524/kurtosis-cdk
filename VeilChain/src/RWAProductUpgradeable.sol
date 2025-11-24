// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./interfaces/IKYCRegistry.sol";
import "./interfaces/IAssetRegistry.sol";

/**
 * @title RWAProductUpgradeable
 * @notice RWA 产品抽象合约（债券、基金等）
 * 生命周期：发行 -> 申购 -> 派息 -> 赎回 -> 到期兑付
 */
contract RWAProductUpgradeable is 
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    struct Product {
        bytes32 productId;
        string name;
        address underlyingToken;      // 标的代币（如 USDT）
        uint256 totalSupply;           // 总份额
        uint256 pricePerShare;         // 每份价格（18 位精度）
        uint256 maturityDate;          // 到期日
        uint256 interestRate;          // 年化利率（基点，100 = 1%）
        uint256 issuedAt;              // 发行时间
        ProductStatus status;
    }
    
    enum ProductStatus {
        Pending,       // 待发行
        Active,        // 认购中
        Locked,        // 锁定期
        Matured,       // 已到期
        Defaulted      // 违约
    }
    
    IKYCRegistry public kycRegistry;
    IAssetRegistry public assetRegistry;
    
    mapping(bytes32 => Product) public products;
    mapping(bytes32 => mapping(address => uint256)) public holdings; // productId => user => shares
    mapping(bytes32 => uint256) public lastInterestDistribution; // productId => timestamp
    
    event ProductIssued(bytes32 indexed productId, string name, uint256 totalSupply);
    event Subscribed(bytes32 indexed productId, address indexed investor, uint256 shares, uint256 amount);
    event Redeemed(bytes32 indexed productId, address indexed investor, uint256 shares, uint256 amount);
    event InterestPaid(bytes32 indexed productId, address indexed investor, uint256 amount, uint256 daysHeld);
    event ProductMatured(bytes32 indexed productId);
    event ProductDefaulted(bytes32 indexed productId);
    event ProductStatusChanged(bytes32 indexed productId, ProductStatus oldStatus, ProductStatus newStatus);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(
        address admin_,
        address kycRegistry_,
        address assetRegistry_
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ISSUER_ROLE, admin_);
        _grantRole(OPERATOR_ROLE, admin_);
        
        kycRegistry = IKYCRegistry(kycRegistry_);
        assetRegistry = IAssetRegistry(assetRegistry_);
    }
    
    /// @notice 发行产品
    function issueProduct(
        bytes32 productId,
        string memory name,
        address underlyingToken,
        uint256 totalSupply,
        uint256 pricePerShare,
        uint256 maturityDate,
        uint256 interestRate
    ) external onlyRole(ISSUER_ROLE) {
        require(products[productId].productId == bytes32(0), "Product exists");
        require(underlyingToken != address(0), "Invalid token");
        require(totalSupply > 0, "Invalid supply");
        require(pricePerShare > 0, "Invalid price");
        require(maturityDate > block.timestamp, "Invalid maturity");
        require(interestRate <= 10000, "Rate too high"); // 最大 100%
        
        products[productId] = Product({
            productId: productId,
            name: name,
            underlyingToken: underlyingToken,
            totalSupply: totalSupply,
            pricePerShare: pricePerShare,
            maturityDate: maturityDate,
            interestRate: interestRate,
            issuedAt: block.timestamp,
            status: ProductStatus.Active
        });
        
        lastInterestDistribution[productId] = block.timestamp;
        
        emit ProductIssued(productId, name, totalSupply);
    }
    
    /// @notice 申购
    function subscribe(bytes32 productId, uint256 shares) external whenNotPaused {
        require(kycRegistry.isKYCApproved(msg.sender), "KYC required");
        
        Product storage product = products[productId];
        require(product.status == ProductStatus.Active, "Not active");
        require(shares > 0 && shares <= product.totalSupply, "Invalid shares");
        
        uint256 amount = shares * product.pricePerShare / 1e18;
        
        // 完整的转账逻辑
        IERC20Upgradeable token = IERC20Upgradeable(product.underlyingToken);
        token.safeTransferFrom(msg.sender, address(this), amount);
        
        holdings[productId][msg.sender] += shares;
        product.totalSupply -= shares;
        
        emit Subscribed(productId, msg.sender, shares, amount);
    }
    
    /// @notice 赎回
    function redeem(bytes32 productId, uint256 shares) external whenNotPaused {
        require(holdings[productId][msg.sender] >= shares, "Insufficient shares");
        
        Product storage product = products[productId];
        require(product.status == ProductStatus.Active, "Not redeemable");
        
        uint256 amount = shares * product.pricePerShare / 1e18;
        
        // 完整的转账逻辑
        IERC20Upgradeable token = IERC20Upgradeable(product.underlyingToken);
        token.safeTransfer(msg.sender, amount);
        
        holdings[productId][msg.sender] -= shares;
        product.totalSupply += shares;
        
        emit Redeemed(productId, msg.sender, shares, amount);
    }
    
    /// @notice 派息
    /// @param productId 产品 ID
    /// @param investors 投资者地址列表
    /// @param daysHeld 持有天数（用于计算利息）
    function distributeInterest(
        bytes32 productId, 
        address[] calldata investors,
        uint256 daysHeld
    ) 
        external 
        onlyRole(OPERATOR_ROLE) 
    {
        Product storage product = products[productId];
        require(product.status == ProductStatus.Locked || product.status == ProductStatus.Active, "Invalid status");
        require(daysHeld > 0 && daysHeld <= 365, "Invalid days");
        
        IERC20Upgradeable token = IERC20Upgradeable(product.underlyingToken);
        
        for (uint256 i = 0; i < investors.length; i++) {
            address investor = investors[i];
            uint256 shares = holdings[productId][investor];
            if (shares == 0) continue;
            
            // 正确的利息计算公式：本金 * 年化利率 * 天数 / 365 / 10000
            uint256 principal = shares * product.pricePerShare;
            uint256 interest = principal * product.interestRate * daysHeld / 365 / 10000 / 1e18;
            
            if (interest > 0) {
                token.safeTransfer(investor, interest);
                emit InterestPaid(productId, investor, interest, daysHeld);
            }
        }
        
        lastInterestDistribution[productId] = block.timestamp;
    }
    
    /// @notice 到期兑付
    function settleMaturity(bytes32 productId, address[] calldata investors) 
        external 
        onlyRole(OPERATOR_ROLE) 
    {
        Product storage product = products[productId];
        require(block.timestamp >= product.maturityDate, "Not matured");
        require(product.status != ProductStatus.Defaulted, "Defaulted");
        
        ProductStatus oldStatus = product.status;
        product.status = ProductStatus.Matured;
        emit ProductStatusChanged(productId, oldStatus, ProductStatus.Matured);
        
        IERC20Upgradeable token = IERC20Upgradeable(product.underlyingToken);
        
        // 计算从最后一次派息到到期的天数
        uint256 daysToMaturity = (product.maturityDate - lastInterestDistribution[productId]) / 1 days;
        
        for (uint256 i = 0; i < investors.length; i++) {
            address investor = investors[i];
            uint256 shares = holdings[productId][investor];
            if (shares == 0) continue;
            
            // 计算本金
            uint256 principal = shares * product.pricePerShare / 1e18;
            
            // 计算剩余利息
            uint256 finalInterest = shares * product.pricePerShare * product.interestRate * daysToMaturity / 365 / 10000 / 1e18;
            
            // 转账本金 + 最终利息
            uint256 totalPayout = principal + finalInterest;
            if (totalPayout > 0) {
                token.safeTransfer(investor, totalPayout);
            }
            
            holdings[productId][investor] = 0;
        }
        
        emit ProductMatured(productId);
    }
    
    /// @notice 违约处置
    function declareDefault(bytes32 productId) external onlyRole(OPERATOR_ROLE) {
        Product storage product = products[productId];
        require(product.status != ProductStatus.Matured, "Already matured");
        
        ProductStatus oldStatus = product.status;
        product.status = ProductStatus.Defaulted;
        emit ProductStatusChanged(productId, oldStatus, ProductStatus.Defaulted);
        emit ProductDefaulted(productId);
    }
    
    /// @notice 更改产品状态（如从 Active 切换到 Locked）
    function setProductStatus(bytes32 productId, ProductStatus newStatus) 
        external 
        onlyRole(OPERATOR_ROLE) 
    {
        Product storage product = products[productId];
        require(product.productId != bytes32(0), "Product not exists");
        
        ProductStatus oldStatus = product.status;
        require(oldStatus != newStatus, "Status unchanged");
        
        product.status = newStatus;
        emit ProductStatusChanged(productId, oldStatus, newStatus);
    }
    
    uint256[47] private __gap; // 预留 47 个槽（增加了 lastInterestDistribution 占 1 个）
}

