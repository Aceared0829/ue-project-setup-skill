# PIE input and HUD pass-through

## Symptom → cause → fix

| Symptom | Cause | Fix |
| --- | --- | --- |
| Cursor leaves the PIE window, no capture | `FInputModeGameOnly` never applied; engine only set the capture mode from `InputSettings` without `LockMouseToWidget` | `SetInputMode(FInputModeGameOnly())` + `bShowMouseCursor=false` in `BeginPlay` |
| Mouse moves, camera doesn't turn | HUD/Slate widget eats `OnMouseMove`/`OnMouseButtonDown` (returns `Handled`, captures mouse) | `HitTestInvisible` on widget and on `TakeWidget()` result |
| Keyboard dead after clicking HUD | Widget called `SetUserFocus` on click | same `HitTestInvisible`; HUD must not be focusable |
| Input works in standalone, not in embedded PIE | Embedded PIE never activates the host window, so the platform layer drops deltas | `FSlateApplication::Get().ActivateGameViewport()` |
| Capture lost after alt-tab / first frames | Widget tree not ready on the first tick | retry next tick, then every 0.1 s, ~5 attempts |
| Look turns but is sluggish / jittery | no high-precision relative mouse | `UseHighPrecisionMouseMovement` in the capture reply |

## Controller-side pattern

In `BeginPlay` (local PC only):

```cpp
SetInputMode(FInputModeGameOnly());
bShowMouseCursor = false;

MouseCaptureRetriesRemaining = 5;
World->GetTimerManager().SetTimerForNextTick(
    FTimerDelegate::CreateWeakLambda(this, [this]()
    {
        if (!AcquireGameMouseCapture()) { ScheduleMouseCaptureRetry(); }
    }));
```

Acquire:

```cpp
GameViewport->SetMouseCaptureMode(EMouseCaptureMode::CapturePermanently_IncludingInitialMouseDown);
GameViewport->SetMouseLockMode(EMouseLockMode::LockOnCapture);
GameViewport->SetIgnoreInput(false);

FSlateApplication::Get().ActivateGameViewport(); // native window focus + OnViewportActivated

TSharedPtr<SViewport> ViewportWidget = GameViewport->GetGameViewportWidget();
if (!ViewportWidget->HasMouseCapture())
{
    FSlateApplication::Get().SetAllUserFocusToGameViewport(EFocusCause::SetDirectly);

    FWidgetPath PathToViewport;
    FSlateApplication::Get().GeneratePathToWidgetUnchecked(
        ViewportWidget.ToSharedRef(), PathToViewport, EVisibility::All);

    const FReply CaptureReply = FReply::Handled()
        .PreventThrottling()
        .SetUserFocus(ViewportWidget.ToSharedRef(), EFocusCause::SetDirectly)
        .CaptureMouse(ViewportWidget.ToSharedRef())
        .LockMouseToWidget(ViewportWidget.ToSharedRef())
        .UseHighPrecisionMouseMovement(ViewportWidget.ToSharedRef());
    FSlateApplication::Get().ProcessReply(PathToViewport, CaptureReply, nullptr, nullptr);
}
```

Success test is `HasMouseCapture() && (HasKeyboardFocus() || HasFocusedDescendants())`.
Release on `EndPlay`: `SetMouseCaptureMode(EMouseCaptureMode::NoCapture)` and
clear the retry timer.

`FSceneViewport::AcquireFocusAndCapture` is private in UE 5.8 — the reply above
reproduces everything it does except the window activation, which
`ActivateGameViewport()` already handled.

## HUD pass-through

`pointer-events: none` in `.rcss`, or `SelfHitTestInvisible` on the UMG widget,
only affects their own hit-testing. Slate routing still reaches the widget.
RmlUi's `SRmlUiWidget::OnMouseMove`/`OnMouseButtonDown` return `Handled` and
capture the mouse, so the widget itself must be invisible to hit-testing:

```cpp
RmlWidget->SetVisibility(ESlateVisibility::HitTestInvisible);
TSharedPtr<SWidget> ViewportContent = RmlWidget->TakeWidget();
ViewportContent->SetVisibility(EVisibility::HitTestInvisible); // UWidget visibility doesn't always propagate
GameViewport->AddViewportWidgetContent(ViewportContent.ToSharedRef(), ZOrder);
```

## Diagnostics that actually discriminate

Add a console command that prints, at once:

- `GameViewport->GetMouseCaptureMode()` / `GetMouseLockMode()`
- `ViewportWidget->HasMouseCapture()`, `HasKeyboardFocus()`
- `FSlateApplication::Get().HasAnyMouseCaptor()`
- `GetUserFocusedWidget(0)` / `GetKeyboardFocusedWidget()` type names
- pawn location + velocity

A "recapture" command calling the acquire function is worth more than restarting
PIE when tuning this.

For Enhanced Input specifically, log once (non-shipping) the first non-zero
`Move` and `Look` values. Capture can be correct while mapping contexts are
wrong; the values prove which layer is broken.

## Things that look like bugs but aren't

- `LogSlate: Could not find Glyph Index ... U+FFA8 ... DroidSansFallback.ttf` —
  editor font fallback noise, unrelated to the HUD.
- A crash inside `FSimpleAssetEditor` on shutdown is asset-editor teardown, not
  the input fix.
