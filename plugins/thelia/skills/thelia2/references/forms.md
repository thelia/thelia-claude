# Thelia 2.6: Forms

> Source: `core/lib/Thelia/Form/BaseForm.php:44`, `core/lib/Thelia/Core/Template/ParserContext.php:31`. Forms are Symfony Form under the hood, with a Thelia-specific layer (auto CSRF, `success_url` / `error_url` channels, non-constructor `init()`).

## 1. BaseForm.init() non-constructor (anti-pattern vs SF 6+)

```php
abstract class BaseForm implements FormInterface  // BaseForm.php:44
{
    public function init(
        Request $request,
        EventDispatcherInterface $eventDispatcher,
        TranslatorInterface $translator,
        FormFactoryBuilderInterface $formFactoryBuilder,
        ValidatorBuilder $validationBuilder,
        TokenStorageInterface $tokenStorage,
        string $type = FormType::class,
        array $data = [],
        array $options = []
    ): void  // BaseForm.php:102

    abstract protected function buildForm(): void;  // BaseForm.php:427
}
```

`init()` is the real entry point, not the constructor. Instantiation goes through `thelia.form_factory` which calls `init()` after `new` (SIGNAL-13). This is incompatible with standard SF 6 constructor injection; anticipate this in T3.

## 2. getName() auto FQCN snake_case

`BaseForm.php:394-406`:

```php
// CustomerFamily\Form\AddCustomerFamilyForm -> customerfamily_form_add_customer_family_form
public static function getName(): string;
```

Override possible if you want a short or business name:

```php
final class ContactForm extends BaseForm
{
    public static function getName(): string
    {
        return 'mymodule_contact';
    }

    protected function buildForm(): void
    {
        $this->formBuilder
            ->add('email', \Symfony\Component\Form\Extension\Core\Type\EmailType::class, [
                'constraints' => [new \Symfony\Component\Validator\Constraints\NotBlank()],
            ])
            ->add('message', \Symfony\Component\Form\Extension\Core\Type\TextareaType::class);
    }
}
```

Collision possible if two modules have the same final class in two namespaces, though unlikely in practice.

## 3. Auto CSRF

Enabled by default (`BaseForm.php:123-131`). `CsrfExtension` + `CsrfTokenManager`. Can be disabled via `$options['csrf_protection'] = false`; **refuse in review**.

The token is rendered by `{form_hidden_fields}` Smarty.

## 4. Auto hidden fields: success_url / error_url / error_message

`init()` systematically adds (`BaseForm.php:161-178`):

| Field | Role |
|---|---|
| `success_url` | redirect after success (read by `getSuccessUrl()`) |
| `error_url` | redirect after failure |
| `error_message` | message to display |

Excluded from generated hidden fields (`isTemplateDefinedHiddenField`, lines 226-229). Populate in HTML via:

```smarty
<input type="hidden" name="success_url" value="{url path='/account'}">
<input type="hidden" name="error_url"   value="{url path='/contact'}">
```

### POTENTIAL OPEN-REDIRECT (SIGNAL-16)

`success_url` is passed to `URL::absoluteUrl()` without a whitelist (`BaseForm.php:296-308`). An attacker can forge an external URL via the form if the HTML accepts it.

**Whitelist to audit in review**: patch any module that renders a public form:

```php
// In the controller, after validateForm():
$successUrl = $form->get('success_url')->getData();
if (!$this->isInternalUrl($successUrl)) {
    throw new \Symfony\Component\HttpKernel\Exception\BadRequestHttpException();
}
```

Recommended helper: check that `parse_url($url, PHP_URL_HOST)` is null OR equals `$request->getHost()`.

## 5. Events FORM_BEFORE_BUILD / FORM_AFTER_BUILD

`init()` dispatches (`BaseForm.php:144-156`):
- `TheliaEvents::FORM_BEFORE_BUILD.{name}` (`thelia.form.before_build`)
- `TheliaEvents::FORM_AFTER_BUILD.{name}` (`thelia.form.after_build`)

This is the official extension point for adding fields from an external module, preferable to back hooks that inject HTML outside `FormType` (not validated by Symfony Form).

```php
<?php
declare(strict_types=1);

namespace MyModule\EventListener;

use Symfony\Component\EventDispatcher\Attribute\AsEventListener;
use Thelia\Core\Event\TheliaFormEvent;
use Thelia\Core\Event\TheliaEvents;
use Symfony\Component\Form\Extension\Core\Type\TextType;

#[AsEventListener(event: TheliaEvents::FORM_AFTER_BUILD.'.thelia_customer_create')]
final class ExtendCustomerForm
{
    public function __invoke(TheliaFormEvent $event): void
    {
        $event->getForm()->getFormBuilder()->add('extra_field', TextType::class);
    }
}
```

## 6. ParserContext: Smarty errors

```php
// ParserContext.php:31
$parserContext->addForm($form);              // serializes errors in session under form_error_information
$parserContext->setGeneralError('message');  // global message
$parserContext->getForm($id, $class, $type); // retrieve errored form on template side via {form name="..."}
```

`BaseController::validateForm()` (`BaseController.php:263-271`) calls `clearForm($form)` after success. On failure, the controller must call `$this->getParserContext()->addForm($form)` then `generateErrorRedirect($form)`. Errors survive in session for the next request.

## 7. BaseFrontController / BaseAdminController helpers

```php
$form = $this->createForm(MyForm::class);
try {
    $validated = $this->validateForm($form);    // CSRF + method + validators
    // do action
    return $this->generateSuccessRedirect($form);
} catch (FormValidationException $e) {
    return $this->generateErrorRedirect($form);  // ParserContext::addForm() already called
}
```

Routing convention: no URL -> form mapping. The controller resolves via `BaseController::createForm($name, $type)` which goes through `thelia.form_factory`.

## 8. Smarty rendering of a form

```smarty
{form name="mymodule_contact"}
    {render_form_field field="email"}
    {render_form_field field="message"}
    {form_error field="email"}                  {* field errors *}
    {form_hidden_fields form=$form}             {* CSRF + other hidden fields *}
    <input type="hidden" name="success_url" value="{url path='/contact-thanks'}">
    <input type="hidden" name="error_url"   value="{url path='/contact'}">
    <button type="submit">Send</button>
{/form}
```

## 9. MapRequestPayload SF 6.3+

**NOT used internally in T2.6** (no occurrence in the core). Available if a SF 6.3+ module wants to use it for a modern form-driven controller (recommended for new REST API or JSON-driven controllers, outside classic HTML web forms):

```php
#[Route('/api/mymodule/items', methods: ['POST'])]
public function create(
    #[MapRequestPayload] CreateItemDto $dto,
): JsonResponse {
    // ...
}
```

Reserve for non-Smarty endpoints (API, AJAX). For classic HTML web forms, keep the `BaseForm` + `validateForm()` pattern because it integrates `ParserContext` for Smarty errors.

## 10. Form pitfalls

1. Non-constructor `init()` -> incompatible with constructor injection (SIGNAL-13)
2. `success_url` / `error_url` potential open-redirect without whitelist (SIGNAL-16)
3. CSRF disableable via `$options['csrf_protection'] = false` -> refuse in review
4. `getName()` static auto FQCN snake_case: collision possible if two modules have same final class (unlikely)
5. `FORM_AFTER_BUILD` is the only clean extension point for adding fields; do NOT inject HTML via back hook (not validated by Symfony Form)
6. The CSRF token must always be rendered via `{form_hidden_fields}`; bypassing it invalidates submission
7. **IBAN validation rejecting spaces**: users always paste their IBAN formatted with spaces (`FR76 3000 6000 0112 3456 7890 189`). A regex `/^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$/` rejects them systematically. Either normalize in a `PRE_SUBMIT` listener (`str_replace(' ', '', $iban)`) or widen the regex and then normalize on the repository side before persisting.
8. **TextareaType without `Length(['max' => N])`**: the `module_config.value` column is `LONGTEXT` MySQL, so no crash, but it allows injecting several MB of content. Always bound it.

## 11. IBAN normalization: type pattern

```php
use Symfony\Component\Form\Event\PreSubmitEvent;
use Symfony\Component\Form\FormEvents;

protected function buildForm(): void
{
    $this->formBuilder
        ->add('iban', TextType::class, [
            'constraints' => [
                new Regex([
                    'pattern' => '/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/',
                    'message' => 'Invalid IBAN format',
                ]),
                new Length(['max' => 34]),
            ],
        ])
        ->addEventListener(FormEvents::PRE_SUBMIT, function (PreSubmitEvent $event): void {
            $data = $event->getData();
            if (isset($data['iban'])) {
                $data['iban'] = strtoupper(str_replace(' ', '', $data['iban']));
                $event->setData($data);
            }
        });
}
```
