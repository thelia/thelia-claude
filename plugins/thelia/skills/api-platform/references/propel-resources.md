# API Platform: Propel/Thelia Resources (Complete Examples)

> **Version note**: The Propel bridge (Thelia 3) remains on **AP 3.x compatibility mode**. The AP 4.2 features (ObjectMapper, JsonStreamer, Metadata Mutators, QueryParameter, Link Provider) **do not apply** to the Propel bridge. Continue using the patterns below: `#[ApiFilter]`, `PropelResourceInterface`, `ResourceAddonInterface`. Doctrine (standard Symfony) projects use the AP 4.2+ patterns documented in `doctrine-resources.md` and the main SKILL.md.

## Contents

- Simple Resource
- Translatable Resource (i18n)
- Relations and Attributes
- Serialization Groups
- Creating with IRI
- Addon (Extending Resources)
- Data Access (Twig/PHP)

## Simple Resource

```php
namespace MyModule\Api\Resource;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Delete;
use ApiPlatform\Metadata\Get;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\Metadata\Post;
use ApiPlatform\Metadata\Put;
use Propel\Runtime\Map\TableMap;
use Symfony\Component\Serializer\Attribute\Groups;
use Symfony\Component\Validator\Constraints as Assert;
use Thelia\Api\Bridge\Propel\Attribute\Relation;
use Thelia\Api\Resource\PropelResourceInterface;
use Thelia\Api\Resource\PropelResourceTrait;
use MyModule\Model\Map\ProductReviewTableMap;

#[ApiResource(
    operations: [
        new Post(uriTemplate: '/admin/product_reviews'),
        new GetCollection(uriTemplate: '/admin/product_reviews'),
        new Get(
            uriTemplate: '/admin/product_reviews/{id}',
            normalizationContext: ['groups' => [self::GROUP_ADMIN_READ, self::GROUP_ADMIN_READ_SINGLE]]
        ),
        new Put(uriTemplate: '/admin/product_reviews/{id}'),
        new Delete(uriTemplate: '/admin/product_reviews/{id}'),
    ],
    normalizationContext: ['groups' => [self::GROUP_ADMIN_READ]],
    denormalizationContext: ['groups' => [self::GROUP_ADMIN_WRITE]],
)]
#[ApiResource(
    operations: [
        new GetCollection(uriTemplate: '/front/product_reviews'),
        new Get(uriTemplate: '/front/product_reviews/{id}'),
    ],
    normalizationContext: ['groups' => [self::GROUP_FRONT_READ]],
)]
class ProductReview implements PropelResourceInterface
{
    use PropelResourceTrait;

    public const GROUP_ADMIN_READ = 'admin:product_review:read';
    public const GROUP_ADMIN_READ_SINGLE = 'admin:product_review:read:single';
    public const GROUP_ADMIN_WRITE = 'admin:product_review:write';
    public const GROUP_FRONT_READ = 'front:product_review:read';

    #[Groups([self::GROUP_ADMIN_READ, self::GROUP_FRONT_READ])]
    public ?int $id = null;

    #[Groups([self::GROUP_ADMIN_READ, self::GROUP_ADMIN_WRITE, self::GROUP_FRONT_READ])]
    #[Assert\NotBlank(groups: [self::GROUP_ADMIN_WRITE])]
    public string $title;

    #[Groups([self::GROUP_ADMIN_READ, self::GROUP_ADMIN_WRITE, self::GROUP_FRONT_READ])]
    public string $content;

    #[Groups([self::GROUP_ADMIN_READ, self::GROUP_ADMIN_WRITE])]
    public int $rating;

    #[Groups([self::GROUP_ADMIN_READ, self::GROUP_FRONT_READ])]
    #[Relation(targetResource: Product::class)]
    public ?Product $product = null;

    public static function getPropelRelatedTableMap(): ?TableMap
    {
        return new ProductReviewTableMap();
    }
}
```

## Translatable Resource (i18n)

```php
namespace MyModule\Api\Resource;

use Thelia\Api\Resource\AbstractTranslatableResource;
use Thelia\Api\Resource\I18n\I18nCollection;

#[ApiResource(
    operations: [
        new GetCollection(uriTemplate: '/admin/my_contents'),
        new Get(uriTemplate: '/admin/my_contents/{id}'),
        new Post(uriTemplate: '/admin/my_contents'),
        new Put(uriTemplate: '/admin/my_contents/{id}'),
    ],
    normalizationContext: ['groups' => [self::GROUP_ADMIN_READ]],
    denormalizationContext: ['groups' => [self::GROUP_ADMIN_WRITE]],
)]
class MyContent extends AbstractTranslatableResource
{
    public const GROUP_ADMIN_READ = 'admin:my_content:read';
    public const GROUP_ADMIN_WRITE = 'admin:my_content:write';

    #[Groups([self::GROUP_ADMIN_READ])]
    public ?int $id = null;

    #[Groups([self::GROUP_ADMIN_READ, self::GROUP_ADMIN_WRITE])]
    public string $code;

    #[Groups([self::GROUP_ADMIN_READ, self::GROUP_ADMIN_WRITE])]
    public I18nCollection $i18ns;

    public static function getI18nResourceClass(): string
    {
        return MyContentI18n::class;
    }

    public static function getPropelRelatedTableMap(): ?TableMap
    {
        return new MyContentTableMap();
    }
}
```

## Relations and Attributes

```php
use Thelia\Api\Bridge\Propel\Attribute\Relation;
use Thelia\Api\Bridge\Propel\Attribute\Column;

// Simple relation
#[Groups([self::GROUP_ADMIN_READ])]
#[Relation(targetResource: Brand::class)]
public ?Brand $brand = null;

// Collection of relations
#[Groups([self::GROUP_ADMIN_READ_SINGLE])]
#[Relation(targetResource: ProductImage::class)]
public array $images = [];

// Force join (eager loading)
#[Relation(targetResource: TaxRule::class, forceJoin: true)]
public TaxRule $taxRule;

// Custom Propel column mapping
#[Column(propelFieldName: 'productSaleElementss')]
#[Relation(targetResource: ProductSaleElements::class)]
public array $productSaleElements = [];
```

## Serialization Groups: Usage on Properties

```php
// Always visible, admin and front
#[Groups([self::GROUP_ADMIN_READ, self::GROUP_FRONT_READ])]
public ?int $id = null;

// Admin only
#[Groups([self::GROUP_ADMIN_READ, self::GROUP_ADMIN_WRITE])]
public string $internalRef;

// Detail view only (not in collections)
#[Groups([self::GROUP_ADMIN_READ_SINGLE, self::GROUP_FRONT_READ_SINGLE])]
public array $images = [];

// Writable
#[Groups([self::GROUP_ADMIN_READ, self::GROUP_ADMIN_WRITE])]
#[Assert\NotBlank(groups: [self::GROUP_ADMIN_WRITE])]
public bool $visible;
```

## Creating with IRI (Relations)

```http
POST /api/admin/products
Content-Type: application/json

{
    "ref": "NEW-PROD-001",
    "visible": true,
    "taxRule": "/api/admin/tax_rules/1",
    "productCategories": [
        {
            "category": "/api/admin/categories/5",
            "defaultCategory": true
        }
    ],
    "i18ns": {
        "fr_FR": {
            "title": "Nouveau produit",
            "description": "Description en francais"
        },
        "en_US": {
            "title": "New product",
            "description": "English description"
        }
    }
}
```

## Addon (Extending Existing Resources)

Structure: `MyModule/Api/Addon/ProductMyAddon.php`

```php
namespace MyModule\Api\Addon;

use Symfony\Component\Serializer\Attribute\Groups;
use Symfony\Component\Serializer\Attribute\Ignore;
use Thelia\Api\Resource\Product;
use Thelia\Model\Product as PropelProduct;

class ProductMyAddon
{
    #[Groups([Product::GROUP_ADMIN_READ, Product::GROUP_FRONT_READ])]
    public ?string $customField = null;

    #[Groups([Product::GROUP_ADMIN_READ])]
    public int $reviewCount = 0;

    #[Ignore]
    public static function buildFromModel(
        PropelProduct $propelModel,
        Product $resource
    ): self {
        $addon = new self();
        $addon->customField = $propelModel->getVirtualColumn('custom_field');
        $addon->reviewCount = ProductReviewQuery::create()
            ->filterByProductId($propelModel->getId())
            ->count();

        return $addon;
    }
}
```

### Addon Rules

- File goes in `MyModule/Api/Addon/`.
- `buildFromModel()` is static with the `#[Ignore]` attribute.
- Use the target resource's group constants (e.g., `Product::GROUP_ADMIN_READ`).
- Each property must have `#[Groups]` to be serialized.
- Before creating a new resource, check whether an existing one can be extended via Addon.

## Data Access

### From Twig

```twig
{# Collection with filters #}
{% set products = resources('/api/front/products', {visible: true, 'order[position]': 'asc'}) %}

{# Single resource #}
{% set product = resources('/api/front/products/' ~ id) %}
```

### From PHP

```php
$products = $this->dataAccessService->resources(
    '/api/front/products',
    ['visible' => true],
    'array'
);
```
