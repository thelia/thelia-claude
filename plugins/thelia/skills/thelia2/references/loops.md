# Thelia 2 - Loop system

## Quick Reference

| Task | Approach |
|-------|----------|
| Display DB data | Propel loop + `PropelSearchLoopInterface` |
| Display computed data | Array loop + `ArraySearchLoopInterface` |
| Loop with i18n | Extend `BaseI18nLoop` |
| Filter results | Arguments in `getArgDefinitions()` |
| Pagination | Arguments `limit`, `page`, `offset` (automatic) |
| Conditional on empty | `{ifloop}` / `{elseloop}` |
| List all loops | `php Thelia loop:list` |

## Smarty syntax

### Basic loop

```smarty
{loop type="product" name="my_products" category="5" limit="10"}
    <div>{$TITLE} - {$BEST_PRICE} EUR</div>
{/loop}
```

### Conditional loop

```smarty
{ifloop rel="my_products"}
    <h2>Our products</h2>
    {loop type="product" name="my_products" category="5"}
        <li>{$TITLE}</li>
    {/loop}
{/ifloop}
{elseloop rel="my_products"}
    <p>No products available</p>
{/elseloop}
```

### Pagination

```smarty
{loop type="product" name="products" limit="12" page="1"}
    <div>{$TITLE}</div>
{/loop}
{pageloop rel="products"}
    {if $PAGE == $CURRENT}<span class="active">{$PAGE}</span>
    {else}<a href="?page={$PAGE}">{$PAGE}</a>{/if}
{/pageloop}
```

`{pageloop}` variables: `$PAGE`, `$CURRENT`, `$LAST`, `$PREV`, `$NEXT`

### Nested loops

```smarty
{loop type="category" name="cats" parent="0"}
    <h2>{$TITLE}</h2>
    {loop type="product" name="prods" category="{$ID}" limit="5"}
        <p>{$TITLE}</p>
    {/loop}
{/loop}
```

## Global arguments and variables

**Arguments** (available on all loops):

| Argument | Description | Default |
|----------|-------------|--------|
| `limit` | Max number of results | unlimited |
| `offset` | Offset of first result | 0 |
| `page` | Page number | - |
| `lang` | Force a language | current language |
| `return_url` | Generate URLs | yes |
| `backend_context` | Admin context | no |

**Output variables**:

| Variable | Condition |
|----------|-----------|
| `$LOOP_COUNT` / `$LOOP_TOTAL` | `$countable = true` |
| `$CREATE_DATE` / `$UPDATE_DATE` | `$timestampable = true` |

## Create a Propel loop

Structure: `MyModule/Loop/MyLoop.php`

```php
<?php
namespace MyModule\Loop;

use MyModule\Model\MyModelQuery;
use Propel\Runtime\ActiveQuery\Criteria;
use Thelia\Core\Template\Element\BaseI18nLoop;
use Thelia\Core\Template\Element\LoopResult;
use Thelia\Core\Template\Element\LoopResultRow;
use Thelia\Core\Template\Element\PropelSearchLoopInterface;
use Thelia\Core\Template\Loop\Argument\Argument;
use Thelia\Core\Template\Loop\Argument\ArgumentCollection;
use Thelia\Type;
use Thelia\Type\TypeCollection;

/**
 * @method int[]    getId()
 * @method bool     getVisible()
 * @method string[] getOrder()
 */
class MyLoop extends BaseI18nLoop implements PropelSearchLoopInterface
{
    protected $timestampable = true;
    protected $countable = true;

    protected function getArgDefinitions()
    {
        return new ArgumentCollection(
            Argument::createIntListTypeArgument('id'),
            Argument::createBooleanOrBothTypeArgument('visible', 1),
            new Argument(
                'order',
                new TypeCollection(
                    new Type\EnumListType(['id', 'id_reverse', 'alpha', 'alpha_reverse', 'manual', 'manual_reverse', 'random'])
                ),
                'manual'
            )
        );
    }

    public function buildModelCriteria()
    {
        $search = MyModelQuery::create();
        $this->configureI18nProcessing($search, ['TITLE', 'DESCRIPTION']);

        if (null !== $id = $this->getId()) {
            $search->filterById($id, Criteria::IN);
        }

        $visible = $this->getVisible();
        if ($visible !== Type\BooleanOrBothType::ANY) {
            $search->filterByVisible($visible ? 1 : 0);
        }

        foreach ($this->getOrder() as $order) {
            switch ($order) {
                case 'id':          $search->orderById(Criteria::ASC); break;
                case 'id_reverse':  $search->orderById(Criteria::DESC); break;
                case 'alpha':       $search->addAscendingOrderByColumn('i18n_TITLE'); break;
                case 'alpha_reverse': $search->addDescendingOrderByColumn('i18n_TITLE'); break;
                case 'manual':      $search->orderByPosition(Criteria::ASC); break;
                case 'random':      $search->clearOrderByColumns(); $search->addAscendingOrderByColumn('RAND()'); break 2;
            }
        }
        return $search;
    }

    public function parseResults(LoopResult $loopResult)
    {
        foreach ($loopResult->getResultDataCollection() as $item) {
            $loopResultRow = new LoopResultRow($item);
            $loopResultRow
                ->set('ID', $item->getId())
                ->set('TITLE', $item->getVirtualColumn('i18n_TITLE'))
                ->set('DESCRIPTION', $item->getVirtualColumn('i18n_DESCRIPTION'))
                ->set('VISIBLE', $item->getVisible() ? '1' : '0')
                ->set('POSITION', $item->getPosition())
                ->set('URL', $item->getUrl($this->locale));
            $this->addOutputFields($loopResultRow, $item);
            $loopResult->addRow($loopResultRow);
        }
        return $loopResult;
    }
}
```

Smarty type = class name in kebab-case: `MyLoop` -> `my-loop`

## Create an Array loop

For computed data or external sources (no Propel query).

```php
<?php
namespace MyModule\Loop;

use Thelia\Core\Template\Element\ArraySearchLoopInterface;
use Thelia\Core\Template\Element\BaseLoop;
use Thelia\Core\Template\Element\LoopResult;
use Thelia\Core\Template\Element\LoopResultRow;
use Thelia\Core\Template\Loop\Argument\Argument;
use Thelia\Core\Template\Loop\Argument\ArgumentCollection;

class ConfigLoop extends BaseLoop implements ArraySearchLoopInterface
{
    protected function getArgDefinitions()
    {
        return new ArgumentCollection(
            Argument::createAnyTypeArgument('variable', null, true),
            Argument::createAnyTypeArgument('default')
        );
    }

    public function buildArray()
    {
        return [null];  // Single element for single iteration
    }

    public function parseResults(LoopResult $loopResult)
    {
        foreach ($loopResult->getResultDataCollection() as $item) {
            $loopResultRow = new LoopResultRow();
            $loopResultRow
                ->set('VARIABLE', $this->getVariable())
                ->set('VALUE', $this->getConfigValue($this->getVariable(), $this->getDefault()));
            $loopResult->addRow($loopResultRow);
        }
        return $loopResult;
    }
}
```

## Anti-patterns

| Anti-pattern | Solution |
|--------------|----------|
| Recoding a native loop | `php Thelia loop:list` to check |
| `->find()` in buildModelCriteria | Return un-executed query |
| ArrayLoop for DB data | Use `PropelSearchLoopInterface` |
| Forgetting `configureI18nProcessing` | Call in buildModelCriteria |
| `getTitle()` on i18n columns | `getVirtualColumn('i18n_TITLE')` |
| Variables in lowercase | UPPERCASE: `->set('TITLE', ...)` |
| Duplicate loop names | Unique `name` per page |

## New loop checklist

- [ ] Class in `MyModule/Loop/`, correct namespace
- [ ] Extend `BaseLoop` or `BaseI18nLoop`
- [ ] Implement `PropelSearchLoopInterface` or `ArraySearchLoopInterface`
- [ ] PHPDoc `@method` for magic getters
- [ ] `getArgDefinitions()` with all arguments
- [ ] `buildModelCriteria()` or `buildArray()`
- [ ] `parseResults()` with `LoopResultRow` and UPPERCASE variables
- [ ] Test: `{loop type="my-loop" name="test"}`

---

## Loop argument types

### Simple types

```php
// Integer
Argument::createIntTypeArgument('id', $default, $mandatory, $allowEmpty)

// Float
Argument::createFloatTypeArgument('price')

// Boolean
Argument::createBooleanTypeArgument('visible', false)

// Boolean or "*" (any)
Argument::createBooleanOrBothTypeArgument('visible', Type\BooleanOrBothType::ANY)

// Any string
Argument::createAnyTypeArgument('title')

// Alphanumeric string
Argument::createAlphaNumStringTypeArgument('ref')
```

### List types

```php
// Integer list: id="1,2,3"
Argument::createIntListTypeArgument('id')

// Any list: ref="ABC,DEF"
Argument::createAnyListTypeArgument('ref')

// Enum list
Argument::createEnumListTypeArgument('order', ['alpha', 'manual', 'random'])
```

### Custom type

```php
new Argument(
    'order',
    new TypeCollection(
        new Type\EnumListType(['alpha', 'manual', 'random'])
    ),
    'alpha'  // default value
)

// Multiple possible types
new Argument(
    'customer',
    new TypeCollection(
        new Type\IntType(),
        new Type\EnumType(['current', '*'])
    ),
    'current'
)
```

---

## i18n handling in loops

### Configuration in buildModelCriteria()

```php
public function buildModelCriteria()
{
    $search = MyModelQuery::create();

    // Translated columns to retrieve
    $this->configureI18nProcessing(
        $search,
        ['TITLE', 'CHAPO', 'DESCRIPTION', 'POSTSCRIPTUM']
    );

    return $search;
}
```

### Accessing values in parseResults()

```php
public function parseResults(LoopResult $loopResult)
{
    foreach ($loopResult->getResultDataCollection() as $item) {
        $loopResultRow = new LoopResultRow($item);

        // i18n columns via getVirtualColumn()
        $loopResultRow
            ->set('TITLE', $item->getVirtualColumn('i18n_TITLE'))
            ->set('DESCRIPTION', $item->getVirtualColumn('i18n_DESCRIPTION'))
            ->set('IS_TRANSLATED', $item->getVirtualColumn('IS_TRANSLATED'))
            ->set('LOCALE', $this->locale);

        $loopResult->addRow($loopResultRow);
    }

    return $loopResult;
}
```

### Key points

- Always call `configureI18nProcessing()` in `buildModelCriteria()` BEFORE using i18n columns
- i18n columns are prefixed `i18n_` in virtual columns
- `IS_TRANSLATED` is automatically available after `configureI18nProcessing()`
- `$this->locale` contains the current loop locale
- NEVER use `$item->getTitle()` directly for i18n columns; use `getVirtualColumn('i18n_TITLE')`
- Extend `BaseI18nLoop` instead of `BaseLoop` for translated entities

---

## Native Thelia 2 loops

### Commerce

| Loop | Usage | Key args |
|------|-------|----------------|
| `product` | Products | `category`, `new`, `promo`, `visible`, `order` |
| `category` | Categories | `parent`, `visible`, `exclude` |
| `product-sale-elements` | Product variants | `product`, `promo`, `new` |
| `cart` | Cart | - |
| `order` | Orders | `customer`, `status`, `order` |
| `customer` | Customers | `current`, `with_order` |

### Content

| Loop | Usage | Key args |
|------|-------|----------------|
| `content` | Content | `folder`, `visible` |
| `folder` | Folders | `parent`, `visible` |
| `image` | Images | `product`, `category`, `width`, `height`, `resize_mode` |
| `document` | Documents | `product`, `category` |

### Catalog

| Loop | Usage | Key args |
|------|-------|----------------|
| `brand` | Brands | `product`, `visible` |
| `feature` | Features | `product`, `exclude` |
| `feature-value` | Feature values | `feature`, `product` |
| `attribute` | Attributes | `product`, `exclude` |

### Utilities

| Loop | Usage | Key args |
|------|-------|----------------|
| `lang` | Languages | `active`, `visible` |
| `currency` | Currencies | `visible` |
| `country` | Countries | `area`, `visible` |
| `module` | Modules | `type`, `active` |

### Search arguments

For searchable loops:

```smarty
{loop type="product" name="search_results"
      search_term="shoe"
      search_in="title,description"
      search_mode="any_word"}
    <div>{$TITLE}</div>
{/loop}
```

| Argument | Description |
|----------|-------------|
| `search_term` | Term to search |
| `search_in` | Fields (title, description, chapo, ref) |
| `search_mode` | `any_word`, `sentence`, `strict_sentence` |

For the complete list of 73 native loops and their arguments, see `php Thelia loop:list`.

---

## Common pitfalls

### Namespace in Smarty type

```smarty
{* WRONG: full class name *}
{loop type="MyModule\Loop\MyLoop" name="test"}

{* CORRECT: automatic kebab-case conversion *}
{loop type="my-loop" name="test"}
```

### Returning instead of set()

```php
// WRONG
public function parseResults(LoopResult $loopResult)
{
    return ['ID' => 1, 'TITLE' => 'Test'];
}

// CORRECT
public function parseResults(LoopResult $loopResult)
{
    $row = new LoopResultRow();
    $row->set('ID', 1)->set('TITLE', 'Test');
    $loopResult->addRow($row);
    return $loopResult;
}
```

### Direct access to i18n columns

```php
// WRONG: i18n column not directly available
$item->getTitle()

// CORRECT: after configureI18nProcessing()
$item->getVirtualColumn('i18n_TITLE')
```

### Duplicate loop names

```smarty
{* WRONG: same name reused *}
{loop type="product" name="products"}{/loop}
{loop type="category" name="products"}{/loop}

{* CORRECT: unique names per page *}
{loop type="product" name="featured_products"}{/loop}
{loop type="category" name="main_categories"}{/loop}
```

### Executing the query in buildModelCriteria

```php
// WRONG: do not call ->find()
public function buildModelCriteria()
{
    return MyModelQuery::create()->find(); // NO!
}

// CORRECT: return the un-executed query
public function buildModelCriteria()
{
    return MyModelQuery::create(); // Thelia executes it
}
```

### Variables in lowercase

```php
// WRONG
$row->set('title', $item->getTitle());

// CORRECT: always UPPERCASE
$row->set('TITLE', $item->getVirtualColumn('i18n_TITLE'));
```
