# Thelia 2: Propel ORM

## Quick reference

| Task | Approach |
|---|---|
| Define table | `Config/schema.xml` |
| Generate models | `php Thelia module:generate:model MyModule --generate-sql` |
| Simple query | `MyModelQuery::create()->filterByX()->find()` |
| Query with join | `->useRelationQuery()...->endUse()` |
| Transaction | `$con->beginTransaction()` / `commit()` / `rollback()` |
| Extend model | Class in `Model/MyModel.php` (not Base) |

## Key principles

- **Database name**: always `TheliaMain` (not `Thelia`)
- **Namespace**: `namespace="MyModule\Model"` in schema.xml
- **external-schema**: required for FKs toward Thelia tables: `<external-schema filename="local/config/schema.xml" referenceOnly="true" />`
- **Never modify** `Base/` files (regenerated) or native Thelia tables
- **Extension tables**: to add fields to a Thelia table, create a `table_extension` with FK

## schema.xml: essential patterns

```xml
<database defaultIdMethod="native" name="TheliaMain" namespace="MyModule\Model">
    <table name="my_module_item">
        <column autoIncrement="true" name="id" primaryKey="true" required="true" type="INTEGER" />
        <column name="ref" required="true" size="255" type="VARCHAR" />
        <column name="customer_id" type="INTEGER" />

        <foreign-key foreignTable="customer" name="fk_item_customer" onDelete="CASCADE">
            <reference foreign="id" local="customer_id" />
        </foreign-key>

        <index name="idx_customer_id">
            <index-column name="customer_id" />
        </index>

        <behavior name="timestampable" />
        <behavior name="i18n">
            <parameter name="i18n_columns" value="title, description, chapo" />
        </behavior>
    </table>

    <external-schema filename="local/config/schema.xml" referenceOnly="true" />
</database>
```

**Many-to-many table**: `<table isCrossRef="true" name="product_tag">` with 2 FKs as composite PK.

## Behaviors

| Behavior | Effect | Usage |
|---|---|---|
| `timestampable` | Adds `created_at` / `updated_at` | Almost always |
| `i18n` | Creates `*_i18n` table | Translatable columns |
| `versionable` | Change history | Audit trail |

## Queries: essential patterns

```php
// Base: findPk, findOne, find, count
$item = MyItemQuery::create()->findPk($id);
$items = MyItemQuery::create()->filterByVisible(1)->find();

// Criteria: IN, GREATER_THAN, LESS_THAN, LIKE, ISNULL, NOT_EQUAL
->filterById([1, 2, 3], Criteria::IN)
->filterByPrice(100, Criteria::GREATER_THAN)

// Joins: useQuery/endUse (supports nesting)
->useCustomerQuery()->filterByEmail('x@y.com')->endUse()

// Calculated columns
->withColumn('SUM(quantity * price)', 'total_amount')
// Access: $item->getVirtualColumn('total_amount')
```

## Model extension

- **Model**: `Model/MyItem.php extends Base\MyItem`. Hooks: `preInsert`, `preSave`, `postSave`, `preDelete`.
- **Query**: `Model/MyItemQuery.php extends Base\MyItemQuery`. Custom methods (scopes).

## Transactions

```php
$con = Propel::getWriteConnection(MyItemTableMap::DATABASE_NAME);
$con->beginTransaction();
try {
    $item->save($con);
    $relation->save($con);
    $con->commit();
} catch (\Exception $e) {
    $con->rollback();
    throw $e;
}
```

## CLI commands

```bash
php Thelia module:generate:model MyModule --generate-sql   # Models + SQL
php Thelia module:generate:sql MyModule                    # SQL only
```

## Anti-patterns

| Anti-pattern | Solution |
|---|---|
| Rewriting existing code | Run Explore agent before coding |
| Modifying `Base/` files | Extend in `Model/MyModel.php` |
| ALTER TABLE on Thelia tables | Extension table with FK |
| N+1 queries in a loop | `joinWith()` or `useXxxQuery()` |
| Multiple operations without transaction | `beginTransaction/commit/rollback` |
| `name="Thelia"` in schema | `name="TheliaMain"` |
| FK without `external-schema` | Add `<external-schema>` |
| Filtered columns without index | Add `<index>` |
| FK without `onDelete` | Always specify `onDelete` |

## New schema checklist

- [ ] `namespace="MyModule\Model"` + `name="TheliaMain"`
- [ ] `external-schema` for Thelia tables
- [ ] Behaviors: `timestampable`, `i18n` as needed
- [ ] FKs with `onDelete` + index on filtered columns
- [ ] `php Thelia module:generate:model MyModule --generate-sql`
- [ ] Extend Model/Query (not Base/)

---

## schema.xml: complete reference

### Base structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<database defaultIdMethod="native" name="TheliaMain" namespace="MyModule\Model">

    <table name="my_module_item">
        <!-- Auto-increment primary key -->
        <column autoIncrement="true" name="id" primaryKey="true" required="true" type="INTEGER" />

        <!-- Common types -->
        <column name="ref" required="true" size="255" type="VARCHAR" />
        <column name="title" size="255" type="VARCHAR" />
        <column name="description" type="CLOB" />
        <column name="chapo" type="LONGVARCHAR" />
        <column name="price" defaultValue="0.00" scale="2" size="10" type="DECIMAL" />
        <column name="position" defaultValue="0" required="true" type="INTEGER" />
        <column name="visible" defaultValue="1" required="true" type="TINYINT" />
        <column name="start_date" type="TIMESTAMP" />

        <!-- Foreign key -->
        <column name="customer_id" type="INTEGER" />

        <foreign-key foreignTable="customer" name="fk_item_customer" onDelete="CASCADE" onUpdate="RESTRICT">
            <reference foreign="id" local="customer_id" />
        </foreign-key>

        <!-- Index -->
        <index name="idx_customer_id">
            <index-column name="customer_id" />
        </index>

        <!-- Unique constraint -->
        <unique name="ref_UNIQUE">
            <unique-column name="ref" />
        </unique>

        <!-- Behaviors -->
        <behavior name="timestampable" />

        <behavior name="i18n">
            <parameter name="i18n_columns" value="title, description, chapo" />
        </behavior>
    </table>

    <!-- Reference to Thelia schema (required for foreign keys) -->
    <external-schema filename="local/config/schema.xml" referenceOnly="true" />
</database>
```

### Column types

| Type | Usage | Options |
|---|---|---|
| `INTEGER` | Integer | `autoIncrement`, `primaryKey` |
| `VARCHAR` | Short text | `size="255"` |
| `LONGVARCHAR` | Medium text | none |
| `CLOB` | Long text | none |
| `DECIMAL` | Decimal | `size="10" scale="2"` |
| `TINYINT` | Boolean/small integer | `defaultValue="0"` |
| `TIMESTAMP` | Date and time | none |
| `DATE` | Date only | none |
| `BOOLEAN` | Boolean | none |

### Foreign keys

```xml
<!-- CASCADE: deletes children -->
<foreign-key foreignTable="customer" name="fk_item_customer" onDelete="CASCADE">
    <reference foreign="id" local="customer_id" />
</foreign-key>

<!-- SET NULL: sets to null -->
<foreign-key foreignTable="category" name="fk_item_category" onDelete="SET NULL">
    <reference foreign="id" local="category_id" />
</foreign-key>

<!-- RESTRICT: prevents deletion if children exist -->
<foreign-key foreignTable="product" name="fk_item_product" onDelete="RESTRICT">
    <reference foreign="id" local="product_id" />
</foreign-key>
```

### Many-to-many table

```xml
<table isCrossRef="true" name="product_tag">
    <column name="product_id" primaryKey="true" required="true" type="INTEGER" />
    <column name="tag_id" primaryKey="true" required="true" type="INTEGER" />
    <column name="position" type="INTEGER" />

    <foreign-key foreignTable="product" onDelete="CASCADE">
        <reference foreign="id" local="product_id" />
    </foreign-key>

    <foreign-key foreignTable="my_module_tag" onDelete="CASCADE">
        <reference foreign="id" local="tag_id" />
    </foreign-key>

    <behavior name="timestampable" />
</table>
```

### Behaviors in detail

#### timestampable

Automatically adds `created_at` and `updated_at`.

```xml
<behavior name="timestampable" />
```

#### i18n (internationalization)

Creates a `*_i18n` table with the translated columns.

```xml
<behavior name="i18n">
    <parameter name="i18n_columns" value="title, description, chapo, postscriptum" />
</behavior>
```

#### versionable

Change history.

```xml
<behavior name="versionable">
    <parameter name="log_created_at" value="true" />
    <parameter name="log_created_by" value="true" />
</behavior>
```

### schema.xml pitfalls

#### Never modify native Thelia tables

```sql
-- WRONG: never do this
ALTER TABLE customer ADD COLUMN custom_field VARCHAR(255);
```

#### Create an extension table instead

```xml
<table name="customer_extension">
    <column name="customer_id" primaryKey="true" type="INTEGER" />
    <column name="custom_field" type="VARCHAR" size="255" />
    <foreign-key foreignTable="customer" onDelete="CASCADE">
        <reference foreign="id" local="customer_id" />
    </foreign-key>
</table>
```

#### Database name: always TheliaMain

```xml
<!-- WRONG for Thelia >= 2.5 -->
<database name="Thelia" ...>

<!-- CORRECT -->
<database name="TheliaMain" ...>
```

---

## Propel queries: complete reference

### Base methods

```php
use MyModule\Model\MyItemQuery;
use Propel\Runtime\ActiveQuery\Criteria;

// Find by ID
$item = MyItemQuery::create()->findPk($id);

// Find one result
$item = MyItemQuery::create()
    ->filterByRef('ABC123')
    ->findOne();

// Find all
$items = MyItemQuery::create()
    ->filterByVisible(1)
    ->find();

// Count
$count = MyItemQuery::create()
    ->filterByCustomerId($customerId)
    ->count();
```

### filterBy with Criteria

```php
// Equality (default)
->filterByStatus('active')

// List of values (IN)
->filterById([1, 2, 3], Criteria::IN)
->filterByStatus(['active', 'pending'], Criteria::IN)

// Comparisons
->filterByPrice(100, Criteria::GREATER_THAN)
->filterByPrice(100, Criteria::GREATER_EQUAL)
->filterByPrice(100, Criteria::LESS_THAN)
->filterByPosition(10, Criteria::NOT_EQUAL)

// Dates
->filterByCreatedAt($startDate, Criteria::GREATER_EQUAL)
->filterByCreatedAt($endDate, Criteria::LESS_EQUAL)

// LIKE
->filterByTitle('%keyword%', Criteria::LIKE)

// IS NULL / IS NOT NULL
->filterByCustomerId(null, Criteria::ISNULL)
->filterByCustomerId(null, Criteria::ISNOTNULL)

// BETWEEN (via array)
->filterByPrice(['min' => 10, 'max' => 100])
```

### orderBy and limit

```php
$items = MyItemQuery::create()
    ->orderByPosition(Criteria::ASC)
    ->orderByCreatedAt(Criteria::DESC)
    ->limit(10)
    ->offset(20)
    ->find();
```

### Joins with useQuery/endUse

```php
// Navigate through relations
$items = MyItemQuery::create()
    ->useCustomerQuery()
        ->filterByEmail('test@example.com')
    ->endUse()
    ->find();

// Multiple levels
$orders = OrderQuery::create()
    ->useOrderProductQuery()
        ->useProductQuery()
            ->filterByRef('PROD-001')
        ->endUse()
    ->endUse()
    ->find();

// With optional conditions
$query = MyItemQuery::create();
$subQuery = $query->useCustomerQuery();

if ($customerId !== null) {
    $subQuery->filterById($customerId);
}

$subQuery->endUse();
$items = $query->find();
```

### withColumn (calculated columns)

```php
// Sum
$total = OrderProductQuery::create()
    ->filterByOrderId($orderId)
    ->withColumn('SUM(quantity * price)', 'total_amount')
    ->select(['total_amount'])
    ->findOne();

// Columns from relations
$items = MyItemQuery::create()
    ->joinCustomer('c')
    ->withColumn('c.email', 'customer_email')
    ->find();

// Access via getVirtualColumn
foreach ($items as $item) {
    $email = $item->getVirtualColumn('customer_email');
}
```

---

## Extending Propel models

### Extended model with hooks

```php
<?php
// Model/MyItem.php (not Base/MyItem.php!)

namespace MyModule\Model;

use MyModule\Model\Base\MyItem as BaseMyItem;
use Propel\Runtime\Connection\ConnectionInterface;

class MyItem extends BaseMyItem
{
    public function preInsert(ConnectionInterface $con = null): bool
    {
        if (null === $this->getRef()) {
            $this->setRef($this->generateRef());
        }
        $this->setPosition($this->getNextPosition());
        return true;
    }

    public function preSave(ConnectionInterface $con = null): bool
    {
        // Logic before save
        return true;
    }

    public function postSave(ConnectionInterface $con = null): void
    {
        // Actions after save
    }

    public function preDelete(ConnectionInterface $con = null): bool
    {
        // Cleanup before deletion
        return true;
    }

    protected function generateRef(): string
    {
        $last = MyItemQuery::create()->orderById(Criteria::DESC)->findOne();
        $id = $last ? $last->getId() + 1 : 1;
        return sprintf('ITEM%08d', $id);
    }
}
```

### Extended Query

```php
<?php
// Model/MyItemQuery.php

namespace MyModule\Model;

use MyModule\Model\Base\MyItemQuery as BaseMyItemQuery;
use Propel\Runtime\ActiveQuery\Criteria;

class MyItemQuery extends BaseMyItemQuery
{
    public static function findByRef(string $ref): ?MyItem
    {
        return self::create()->filterByRef($ref)->findOne();
    }

    public function visible(): self
    {
        return $this->filterByVisible(1);
    }

    public function forCustomer(int $customerId): self
    {
        return $this->filterByCustomerId($customerId);
    }
}
```

### Complete transactions

```php
use Propel\Runtime\Propel;
use MyModule\Model\Map\MyItemTableMap;

public function createWithRelations(array $data): MyItem
{
    $con = Propel::getWriteConnection(MyItemTableMap::DATABASE_NAME);
    $con->beginTransaction();

    try {
        $item = new MyItem();
        $item->setRef($data['ref'])->setTitle($data['title'])->save($con);

        foreach ($data['tags'] as $tagId) {
            $itemTag = new MyItemTag();
            $itemTag->setItemId($item->getId())->setTagId($tagId)->save($con);
        }

        $con->commit();
        return $item;
    } catch (\Exception $e) {
        $con->rollback();
        throw $e;
    }
}
```

### Migrations

1. Modify `schema.xml`.
2. Generate SQL: `php Thelia module:generate:model --generate-sql MyModule`.
3. Extract only the differences into `Config/update/1.1.0.sql`.

```sql
ALTER TABLE `my_module_item` ADD `group` VARCHAR(255) DEFAULT NULL;
```

4. Increment version in `module.xml` (1.0.0 to 1.1.0).
5. The `update()` method in `MyModule.php` will run automatically.

**Important**: never modify native Thelia tables. Create an extension table with a foreign key instead.
