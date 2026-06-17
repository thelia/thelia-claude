# Module setup: complete examples

## Summary
- Main module class (postActivation, update, destroy)
- Complete module.xml
- Complete config.xml (services, hooks, loops, forms, commands)

## Main module class

```php
<?php
namespace MyProject;

use Propel\Runtime\Connection\ConnectionInterface;
use Thelia\Install\Database;
use Thelia\Module\BaseModule;

class MyProject extends BaseModule
{
    public const DOMAIN_NAME = 'myproject';

    /**
     * First installation, runs once.
     */
    public function postActivation(ConnectionInterface $con = null): void
    {
        if (!self::getConfigValue('is_initialized', false)) {
            $database = new Database($con);
            $database->insertSql(null, [__DIR__.'/Config/TheliaMain.sql']);
            self::setConfigValue('is_initialized', true);
        }
    }

    /**
     * Version update.
     */
    public function update($currentVersion, $newVersion, ConnectionInterface $con = null): void
    {
        $finder = (new Finder())
            ->files()
            ->name('*.sql')
            ->sortByName()
            ->in(__DIR__.'/Config/update');

        $database = new Database($con);

        foreach ($finder as $file) {
            if (version_compare($currentVersion, $file->getBasename('.sql'), '<')) {
                $database->insertSql(null, [$file->getPathname()]);
            }
        }
    }

    /**
     * Uninstall.
     */
    public function destroy(ConnectionInterface $con = null, $deleteModuleData = false): void
    {
        if ($deleteModuleData) {
            $database = new Database($con);
            $database->insertSql(null, [__DIR__.'/Config/sql/destroy.sql']);
        }
    }
}
```

## module.xml: metadata

```xml
<?xml version="1.0" encoding="UTF-8"?>
<module xmlns="http://thelia.net/schema/dic/module"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://thelia.net/schema/dic/module http://thelia.net/schema/dic/module/module-2_1.xsd">
    <fullnamespace>MyProject\MyProject</fullnamespace>

    <descriptive locale="en_US">
        <title>My Project</title>
        <subtitle>Custom module</subtitle>
        <description>Extended features</description>
    </descriptive>

    <descriptive locale="fr_FR">
        <title>Mon Projet</title>
        <subtitle>Module personnalisé</subtitle>
        <description>Fonctionnalités étendues</description>
    </descriptive>

    <version>1.0.0</version>

    <author>
        <name>Your Name</name>
        <email>you@example.com</email>
    </author>

    <type>classic</type>
    <thelia>2.6.0</thelia>
    <stability>prod</stability>
</module>
```

## config.xml: services and declarations

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<config xmlns="http://thelia.net/schema/dic/config"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://thelia.net/schema/dic/config http://thelia.net/schema/dic/config/thelia-1.0.xsd">

    <loops>
        <loop name="my_entity" class="MyProject\Loop\MyEntityLoop"/>
    </loops>

    <forms>
        <form name="myproject.form.config" class="MyProject\Form\ConfigForm"/>
    </forms>

    <hooks>
        <hook id="myproject.hook.front" class="MyProject\Hook\FrontHook">
            <tag name="hook.event_listener" event="product.additional" type="front" method="onProductTab"/>
        </hook>

        <hook id="myproject.hook.back" class="MyProject\Hook\BackHook">
            <tag name="hook.event_listener" event="main.top-menu-tools" type="back" method="onToolsMenu"/>
        </hook>
    </hooks>

    <services>
        <service id="myproject.service.manager" class="MyProject\Service\DataManager">
            <argument type="service" id="request_stack"/>
            <argument type="service" id="event_dispatcher"/>
        </service>
    </services>

    <commands>
        <command class="MyProject\Command\ImportCommand"/>
    </commands>
</config>
```
