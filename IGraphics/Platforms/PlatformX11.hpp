/*
 ==============================================================================

 This file is part of the iPlug 2 library. Copyright (C) the iPlug 2 developers.

 See LICENSE.txt for  more info.

 ==============================================================================
*/

#pragma once

#include "IPlugPlatform.h"
#include <cstdint>
#include <SDL3/SDL_events.h>

BEGIN_IPLUG_NAMESPACE
BEGIN_IGRAPHICS_NAMESPACE

class PlatformX11;

/// @brief A window-rectangle, representing screen bounds or redraw-areas.
struct WRect
{
  /// @brief left bound
  int32_t x;
  /// @brief top bound
  int32_t y;
  /// @brief width
  uint32_t w;
  /// @brief height
  uint32_t h;
};

/// @brief The configuration options available when creating a new window.
struct WindowOptions
{
  /// @brief Bitmask options for \c flags
  enum EFlags {
    /// @brief Create a window with a GLES context instead of the default OpenGL glx
    USE_GLES = 1<<0,
    /// @brief Enable debug mode for the opengl context
    GL_DEBUG = 1<<1,
  };

  /// @brief The parent window ID, 0 means no parent
  uintptr_t parent = 0;
  /// @brief The major OpenGL / GLES version, 0 means no GL context
  uint16_t glMajor = 0;
  /// @brief The minor OpenGL / GLES version
  uint16_t glMinor = 0;
  /// @brief Any OpenGL / GLES context creation flags
  uint32_t glFlags = 0;
  /// @brief The desired bounds of the window
  WRect bounds;
  /// @brief Other flags
  uint32_t flags;
};

enum PixelFormat {
  /// @brief Pixels are RGB with 8 bits per channel (3 bpp)
  kPF_RGB8 = 1,
  /// @brief Pixels are RGBA with 8 bits per channel (4 bpp)
  kPF_RGBA8 = 2,
};

class X11Window
{
protected:
  /// @brief Pointer to the platform object
  PlatformX11* mPlatform;
  // Remaining implementation fields hidden to simplify the public API.
  // ONLY use this object as a pointer, do NOT try to copy it directly.

  X11Window();
  ~X11Window();

public:
  void Close();

  bool DrawBegin();
  void DrawEnd();

  bool DrawImage(const WRect& bounds, int format, const uint8_t* data);

  /// @brief Set the window as visible or not visible.
  /// @param show true to make this window visible, false to hide it
  void SetVisible(bool show);

  /// @brief Check if the window is currently visible or not.
  /// @return true if visible, false if not
  bool IsVisible() const;

  /**
   * Set the window's title.
   */
  void SetTitle(const char* title);

  /// @brief Take the next event from the list of queued events for
  /// this window, placing it into \c event .
  /// @param event destination for event data
  /// @return true if there was an event, false if not
  bool PollEvent(SDL_Event* event);
};

class PlatformX11
{
private:
  // implementation fields hidden to simplify public API.
  // This struct MUST NOT be copied, it's a pointer-only object.
  char hidden[sizeof(void*) * 20];

  PlatformX11();
  PlatformX11(const PlatformX11&) = delete;
  PlatformX11(PlatformX11&&) = delete;

public:
  /// @brief Create an instance of the platform object.
  static PlatformX11* Create();

  ~PlatformX11();

  /// @brief Create a window using the provided options.
  /// @param options
  /// @return The newly created window, or \c NULL on failure
  X11Window* CreateWindow(const WindowOptions& options);

  /// @brief Process platform-specific events and update all windows
  /// attached to this platform. This is the "main loop" function
  /// and should be called frequently.
  void ProcessEvents();
};


END_IGRAPHICS_NAMESPACE
END_IPLUG_NAMESPACE
