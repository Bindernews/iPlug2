/*
 ==============================================================================

 This file is part of the iPlug 2 library. Copyright (C) the iPlug 2 developers.

 See LICENSE.txt for  more info.

 ==============================================================================
*/

#include "PlatformX11.hpp"
#include "IPlugStructs.h"
#include "IPlugConstants.h"

#include <X11/Xlib.h>
#include <X11/Xlib-xcb.h>
#include <xcb/xcb.h>
#include <xcb/xcb_event.h>
#include <xcb/xcb_icccm.h>
#include <xcb/xfixes.h>
#include <sys/wait.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <time.h>
#include <vector>
#include <memory>
#include <algorithm>
#include <list>

#define XK_3270  // for XK_3270_BackTab
#include <X11/XF86keysym.h>
#include <X11/keysym.h>
#define VKEY_UNSUPPORTED VKEY_UNKNOWN

// glad_gl
// #include <glad/glad.h>
// use GLX loaded by GLAD, linking with glx librariy is required otherwise
#include <glad/glad_glx.h>

#undef TRACE
#ifdef NDEBUG
#define TRACE(...)
#else
#define TRACE printf
#endif

using namespace iplug::igraphics;


// forward declarations
struct XcbPlatform;
struct RealWindow;

/// @brief Size of buffers for X11 error messages
#define XERR_MSG_SIZE (256)

// Source: https://specifications.freedesktop.org/xembed-spec/latest/messages.html

/* XEMBED messages */
#define XEMBED_EMBEDDED_NOTIFY    0
#define XEMBED_WINDOW_ACTIVATE    1
#define XEMBED_WINDOW_DEACTIVATE  2
#define XEMBED_REQUEST_FOCUS      3
#define XEMBED_FOCUS_IN           4
#define XEMBED_FOCUS_OUT          5
#define XEMBED_FOCUS_NEXT         6
#define XEMBED_FOCUS_PREV         7
/* 8-9 were used for XEMBED_GRAB_KEY/XEMBED_UNGRAB_KEY */
#define XEMBED_MODALITY_ON       10
#define XEMBED_MODALITY_OFF      11
#define XEMBED_REGISTER_ACCELERATOR     12
#define XEMBED_UNREGISTER_ACCELERATOR   13
#define XEMBED_ACTIVATE_ACCELERATOR     14

// Source: https://specifications.freedesktop.org/xembed-spec/latest/lifecycle.html
/* Flags for _XEMBED_INFO */
#define XEMBED_MAPPED           (1 << 0)


/// @brief Indexes of the different atoms in \c catoms
enum AtomIds {
  ATOM_WM_PROTOCOLS = 0,
  ATOM_WM_DELETE_WINDOW,
  ATOM_XEMBED_INFO,
  ATOM_XEMBED,
  ATOM_CLIPBOARD,
  ATOM_UTF8_STRING,
  ATOM_XSEL_DATA,
  ATOM_STRING,
  ATOM_TEXT,
  ATOM_TARGETS,
  kAtomIdsCount,
};

struct XcbPlatform
{
  /// @brief Loading status
  enum EConnectionStatus {
    /// @brief Have not attempted to connect
    kNotAttempted = 0,
    /// @brief Tried to load, but failed
    kLoadFailed = 1,
    /// @brief Loaded successfully
    kSuccess = 2,
    /// @brief Loaded with GLX
    kHasGlx = 4,
  };

  /// @brief Private flags for \c WindowOptions
  enum PrivFlags {
    NO_COLORMAP = 1 << 8,
    WM_DECORATIONS = 1 << 9,
  };

  enum MouseMoveMode {
    MOUSE_MOVE_SCREEN,
    MOUSE_MOVE_WINDOW,
    MOUSE_MOVE_RELATIVE,
  };

  //------//
  // Xlib //
  //------//

  /**
   * @brief XErrorHandler typedef
   * @remark The typedef is listed as "not part of the Xlib specification"
   *   so make sure we have our own copy, in case it's not defined?
   */
  typedef int (*_XErrorHandler) (Display*, XErrorEvent*);

  // Pointer to old error handler, returned from XSetErrorHandler
  _XErrorHandler oldErrorHandler;

  /// @brief Xlib display, used for as few things as possible
  Display *dpy;

  //-----//
  // XCB //
  //-----//

  /// @brief XCB connection
  xcb_connection_t *mConn = nullptr;

  /// @brief default X11 screen
  int mDefaultScreen;

  /// @brief Overall loading/connected status
  /// @see EConnectionStatus
  int mStatus = kNotAttempted;

  /// @brief List of available screens
  std::vector<xcb_screen_t*> mScreens;

  /// @brief List of known windows
  std::vector<RealWindow*> mWindows;

  /// @brief Common atoms
  xcb_atom_t catoms[kAtomIdsCount];

  //---------------------------//
  // Clipboard and other state //
  //---------------------------//

  /// @brief Contents of the clipboard, currently only supports UTF-8 / ASCII text
  std::vector<uint8_t> mClipboardData;
  // ID of window that owns clipboard data or 0 if not one of ours
  xcb_window_t mClipboardOwner;

  /// @brief is Ctrl pressed?
  bool mCtrlDown = false;
  /// @brief is Alt pressed?
  bool mAltDown = false;
  /// @brief is Shift pressed?
  bool mShiftDown = false;

  /// @brief Double-click timeout in milliseconds
  /// @remark Default windows double-click timeout is 500ms,
  /// source: https://learn.microsoft.com/en-us/windows/win32/controls/ttm-setdelaytime?redirectedfrom=MSDN
  uint32_t mDblClickTimeout = 500;

  //-----------//
  // Functions //
  //-----------//

  XcbPlatform();
  ~XcbPlatform();

  inline bool HasGLX() const
  { return (mStatus & kHasGlx) != 0; }

  /// @brief Try to connect to the X11 server with xcb. Updates \c mStatus .
  void Connect();

  RealWindow* CreateWindow(const WindowOptions& options);
  RealWindow* CreateBasicWindow(const WindowOptions& options);
  RealWindow* CreateGlxWindow(const WindowOptions& options);

  /**
   * @brief Initializes \c catoms
   */
  void LoadAtoms();

  /**
   * @brief Find and return screen number for xcb <window>.
   * @return -1 in case of errors, the <window> is not found or its screen is not known
   */
  int WindowToScreen(xcb_window_t wnd);

  bool CheckScreenIsTrueColor(int screen) const;

  bool MoveCursor(RealWindow* wnd, MouseMoveMode mode, int cx, int cy);

  /**
   * @brief Process a single X event.
   * @details The event will be propogated to the appropriate child window(s).
   */
  void ProcessXEvent(xcb_generic_event_t* evt);

  /// @brief Process all events currently in the X event queue
  void ProcessEventQueue();

  /**
   * @brief Check if a cookie returned an error or not, printing a message if so
   * @param ck request cookie
   * @return true ON ERROR, so callers can do ``if (CheckCookie(...)) { return ...; }``
   */
  bool CheckCookie(xcb_void_cookie_t ck, const char* prefix) const;

  /// @brief Returns the screen at index \c i or \c NULL
  xcb_screen_t* GetScreen(unsigned i) const
  { return i < mScreens.size() ? mScreens[i] : nullptr; }

  /**
   * @brief Simple wrapper around ``xcb_change_property(mConn, XCB_PROP_MODE_REPLACE, ...)`` for convenience
   */
  void ReplaceProperty(xcb_window_t window, xcb_atom_t property, xcb_atom_t type, uint8_t format, uint32_t data_len, const void* data)
  {
    xcb_change_property(mConn, XCB_PROP_MODE_REPLACE, window, property, type, format, data_len, data);
  }
};

/// @brief The actual implementation of X11Window
struct RealWindow
{
  /// @brief Pointer to the platform object (matches with X11Window)
  PlatformX11* mPlatform;
  /// @brief xcb window reference
  /// @remark `xcb_window_t`
  uint32_t mWnd;
  /// @brief xcb colormap handle
  uint32_t mCmap;
  /// @brief Graphics context, created on-demand for drawing images in software
  xcb_gcontext_t mGc;
  /// @brief Result of glXCreateWindow
  /// @remark `XID`
  uintptr_t mGlWindow;
  /// @brief GL Context
  GLXContext mGlContext;
  /// @brief Tracks paired DrawBegin() and DrawEnd() calls.
  short mInDraw = 0;
  /// @brief Current screen ID this window belongs to
  short mScreen = 0;
  /// @brief Is the window currently visible?
  bool mVisible = false;
  /// @brief Are we locking the cursor?
  bool mCursorLock = false;
  /// @brief If we are locking the cursor, this is where
  xcb_point_t mLock;
  /// @brief Current known cursor position IN the window.
  /// If this is (-1, -1) then the cursor is outside the window.
  xcb_point_t mCursorPos { -1, -1 };

  /// @brief The currently known bounds, may change during update processing
  xcb_rectangle_t mBounds;

  /// @brief Timestamp of last left-click, for checking on double-click events.
  /// @remark This is a uint32, meaning it will wrap at around 49 days. Not a huge issue,
  /// especially since the worst-case scenario is it might eat a double-click once ever 49 days.
  xcb_timestamp_t mLastLeftClickStamp = 0;

  /// @brief Event queue for this window
  std::list<SDL_Event> mEvents;

  //-----------//
  // Functions //
  //-----------//

  RealWindow(XcbPlatform* xp);
  ~RealWindow();

  /// @brief Convert the PlatformX11 pointer into an \c XcbPlatform pointer
  inline XcbPlatform* CastX()
  { return reinterpret_cast<XcbPlatform*>(mPlatform); }

  /// @brief Get the \c xcb_connection_t* this window is bound to
  inline xcb_connection_t* conn()
  { return CastX()->mConn; }

  /// @brief Initialize the window, filling in \c mWnd and \c mCmap
  /// @param options
  /// @param visualId
  /// @return success/failure
  bool Create(const WindowOptions& options, int visualId);

  /// @brief Destroy the window and release associated data.
  void Destroy();

  void SetVisible(bool show);
  void SetTitle(const char* title);
  void EnableEmbed(bool on);

  bool DrawBegin();
  void DrawEnd();

  /// @brief Draw rgba data to the window in the given area
  /// @param area the region of the window to draw in, also used to calculate the size of \c data
  /// @param format the pixel format
  /// @param data pixel data
  /// @return true on success, false on error
  bool DrawImage(const WRect& area, int format, const uint8_t *data);

  bool PutPixels(const xcb_rectangle_t& area, unsigned depth, unsigned data_length, const uint8_t *data);

  xcb_rectangle_t GetBounds();

  void ProcessXEvent(xcb_generic_event_t* ev);

  bool PollEvent(SDL_Event* event);
};

#pragma region static helpers

static iplug::EVirtualKey KeyboardDetailToVirtualKey(unsigned int keysym);

static xcb_get_property_reply_t* GetProperty(
  XcbPlatform* xp, xcb_window_t window, xcb_atom_t property, xcb_atom_t type, uint32_t offset, uint32_t length)
{
  char errbuf[XERR_MSG_SIZE];
  xcb_generic_error_t* err = nullptr;

  auto cookie1 = xcb_get_property(xp->mConn, 0, window, property, type, offset, length);
  xcb_get_property_reply_t* prop = xcb_get_property_reply(xp->mConn, cookie1, &err);
  if (err) {
    XGetErrorText(xp->dpy, err->error_code, errbuf, sizeof(errbuf));
    TRACE("PX11:GetProperty: xcb_get_property failed: %s\n", errbuf);
    free(err);
    return nullptr;
  }
  return prop;
}

static xcb_rectangle_t make_xrect(const WRect& r)
{
  xcb_rectangle_t bb;
  bb.x = (int16_t)r.x;
  bb.y = (int16_t)r.y;
  bb.width = (uint16_t)r.w;
  bb.height = (uint16_t)r.w;
  return bb;
}

#pragma endregion static helpers


//------------------------//
// XcbPlatform implementation //
//------------------------//
#pragma region XcbImpl

/*
 * Log XLib errors for now
 */
static int XlibErrorHandler(Display *dpy, XErrorEvent *ev ){
  char errbuf[XERR_MSG_SIZE];
  XGetErrorText(ev->display, ev->error_code, errbuf, sizeof(errbuf));
  TRACE("XLib error: %s\n", errbuf);
  return 0;
}

XcbPlatform::XcbPlatform()
{
  mStatus = kNotAttempted;
  mClipboardOwner = 0;
}

XcbPlatform::~XcbPlatform()
{
  // close XLib display if it was opened
  if(this->dpy){
      XCloseDisplay(this->dpy);
      this->dpy = NULL;
  }
  if (mConn) {
    xcb_disconnect(mConn);
    mConn = nullptr;
  }
}

void XcbPlatform::Connect()
{
  // if we already have a connection, nothing else to do
  if (mStatus != kNotAttempted) {
    return;
  }

  // track if we got glx
  bool hasGlx = true;

  // default to failing to load
  mStatus = kLoadFailed;

  this->dpy = XOpenDisplay(nullptr);
  if (!this->dpy) {
      TRACE("Could not open X display\n");
      return;
  }

  // Warning: this is global
  this->oldErrorHandler = XSetErrorHandler(&XlibErrorHandler);
  // Load the default screen
  this->mDefaultScreen = DefaultScreen(this->dpy);
  // Grab our xcb connection
  this->mConn = XGetXCBConnection(this->dpy);
  if (!this->mConn) {
      TRACE("Could not get XCB connection for X display\n");
      return;
  }

  // Try to load GLX
  if (!gladLoadGLX(this->dpy, this->mDefaultScreen)) {
    TRACE("Could not load GLX\n");
    hasGlx = false;
  }

  TRACE("INFO: Xlib/XCB FD: %d\n", xcb_get_file_descriptor(mConn));

  // Load atoms for future use
  LoadAtoms();

  // Iterate through screens
  xcb_screen_iterator_t iter = xcb_setup_roots_iterator(xcb_get_setup(mConn));
  for (; iter.rem; xcb_screen_next(&iter)) {
      this->mScreens.push_back(iter.data);
  }

  // Load xfixes extension
  xcb_xfixes_query_version_cookie_t cookie = xcb_xfixes_query_version(mConn, 4, 0);
  xcb_flush(mConn);
  xcb_generic_error_t* err;
  xcb_xfixes_query_version_reply_t* reply = xcb_xfixes_query_version_reply(mConn, cookie, &err);
  if (!reply) {
      printf("Unable to load xfixes extension: codes %d,%d\n", err->major_code, err->minor_code);
      free(err);
      return;
  }
  free(reply);

  // Load successful
  mStatus = kSuccess;
  if (hasGlx) {
    mStatus |= kHasGlx;
  }
}

RealWindow* XcbPlatform::CreateWindow(const WindowOptions& options)
{
#define LOG_PREFIX "PX11:Platform:CreateWindow"
  if (options.flags & WindowOptions::USE_GLES) {
    TRACE(LOG_PREFIX ": GLES not currently implemented\n");
    return nullptr;
  }
  if (options.glMajor > 0) {
    return CreateGlxWindow(options);
  } else {
    return CreateBasicWindow(options);
  }
#undef LOG_PREFIX
}

RealWindow* XcbPlatform::CreateBasicWindow(const WindowOptions& options)
{
#define LOG_PREFIX "PX11:Platform:CreateBasicWindow"
  RealWindow* w = new RealWindow(this);
  int visual_id;

  int screen = WindowToScreen(options.parent);
  if (screen < 0) {
    TRACE(LOG_PREFIX ": could not find parent screen");
    return nullptr;
  }
  if (!CheckScreenIsTrueColor(screen)) {
    TRACE(LOG_PREFIX ":NOT IMPLEMENTED: screen visual is not 24bit RGB, not supported\n");
    return nullptr;
  }
  visual_id = mScreens[screen]->root_visual;

  if (!w->Create(options, visual_id)) {
    delete w;
    return nullptr;
  }

  return w;
#undef LOG_PREFIX
}

RealWindow* XcbPlatform::CreateGlxWindow(const WindowOptions& options)
{
#define LOG_PREFIX "PX11:Platform:CreateWindow"
  // First we need a usable FBConfig
  static int fbcAttr[] = {
    GLX_X_RENDERABLE    , True,             // we want X able draw here
    GLX_DRAWABLE_TYPE   , GLX_WINDOW_BIT,   // we are going to draw a window
    GLX_RENDER_TYPE     , GLX_RGBA_BIT,     // RGBA 8bit per color/alpha
    GLX_X_VISUAL_TYPE   , GLX_TRUE_COLOR,
    GLX_RED_SIZE        , 8,
    GLX_GREEN_SIZE      , 8,
    GLX_BLUE_SIZE       , 8,
    GLX_ALPHA_SIZE      , 8,
    GLX_DEPTH_SIZE      , 24,
    GLX_STENCIL_SIZE    , 8,                // in case we want use stencil (requirement for NanoVG)
    GLX_DOUBLEBUFFER    , True,             // we want double buffer
    //GLX_SAMPLE_BUFFERS  , 1,                // that is nice to have, but not critical. GLX 1.3 could have GLX_ARB_MULTISAMPLE, otherwise had no such attributes.
    //GLX_SAMPLES         , 4,
    None
  };

  int attr[] = {
    GLX_CONTEXT_MAJOR_VERSION_ARB, options.glMajor,
    GLX_CONTEXT_MINOR_VERSION_ARB, options.glMinor,
    GLX_CONTEXT_FLAGS_ARB, /* GLX_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB */ None,
    None
    // GLX_CONTEXT_PROFILE_MASK_ARB, GLX_CONTEXT_CORE_PROFILE_BIT_ARB | GLX_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB, for 3.x+
  };

  // optionally, enable debug mode
  if (options.flags & WindowOptions::GL_DEBUG) {
      attr[5] |= GLX_CONTEXT_DEBUG_BIT_ARB;
  } else {
      attr[4] = 0;
  }

  // Create GLX window
  if (!HasGLX()) {
    TRACE(LOG_PREFIX ": GLX not loaded, cannot create GL window\n");
    return nullptr;
  }

  // auto-deleting FB Config array
  std::unique_ptr<GLXFBConfig, void(*)(void*)> fbcs {nullptr, &free};
  // auto-deleting window
  std::unique_ptr<RealWindow> w {new RealWindow(this)};
  // the visual ID
  int visual_id;

  int fbcCount = 0;
  fbcs.reset(glXChooseFBConfig(this->dpy, mDefaultScreen, fbcAttr, &fbcCount));
  if (!fbcs) {
    TRACE(LOG_PREFIX ": No reasonable FB Configs found\n");
    return nullptr;
  }

  // assume that fbcs[0] will work, since it matches our requirements
  if (glXGetFBConfigAttrib(dpy, fbcs.get()[0], GLX_VISUAL_ID, &visual_id) != 0) {
    TRACE(LOG_PREFIX ":BUG: best FB config has no Visual\n");
    return nullptr;
  }

  GLXContext ctx = nullptr;
  if (glXCreateContextAttribsARB) {
    ctx = glXCreateContextAttribsARB(this->dpy, fbcs.get()[0], 0, true, attr);
    if (!ctx) {
      TRACE(LOG_PREFIX ":GLX: ARB context creation failed\n");
    }
  }
  if (!ctx) {
    // Fall back to default creation method which doesn't allow attributes
    ctx = glXCreateNewContext(dpy, fbcs.get()[0], GLX_RGBA_TYPE, 0, true);
    if (ctx) {
      TRACE(LOG_PREFIX ":GLX: Legacy context creation succeeded\n");
    } else {
      TRACE(LOG_PREFIX ":GLX: Context creation failed\n");
      return nullptr;
    }
  }

  if (!w->Create(options, visual_id)) {
    return nullptr;
  }

  // Register the window with GLX
  w->mGlWindow = glXCreateWindow(this->dpy, fbcs.get()[0], w->mWnd, nullptr);
  if (!w->mGlWindow) {
    TRACE(LOG_PREFIX " Could not create GL window\n");
    return nullptr;
  }

  // return the window, taking it from unique_ptr so it doesn't get free'd
  return w.release();

#undef LOG_PREFIX
}

/*
 * Load some common atoms
 */
void XcbPlatform::LoadAtoms()
{
  static const char *common_atom_names[kAtomIdsCount] = {
    "WM_PROTOCOLS",
    "WM_DELETE_WINDOW",
    "_XEMBED_INFO",
    "_XEMBED",
    "CLIPBOARD",
    "UTF8_STRING",
    "XSEL_DATA",
    "STRING",
    "TEXT",
    "TARGETS",
  };
  if (catoms[0]) {
    return;
  }

  xcb_intern_atom_cookie_t ck[kAtomIdsCount];
  xcb_intern_atom_reply_t *ar;
  int i;
  //TRACE("Loading atoms\n");
  for(i = 0; i < kAtomIdsCount; ++i){
    ck[i] = xcb_intern_atom(mConn, 0, strlen(common_atom_names[i]), common_atom_names[i]);
  }
  for(i = 0; i < kAtomIdsCount; ++i){
    ar = xcb_intern_atom_reply(mConn, ck[i], NULL);
    if (ar) {
      catoms[i] = ar->atom;
      //TRACE(" [%d] %s: 0x%x\n", i, common_atom_names[i], ar->atom);
    } else {
      TRACE("ERROR: could not get atom '%s'\n", common_atom_names[i]);
      catoms[i] = 0;
    }
  }
}

int XcbPlatform::WindowToScreen(xcb_window_t wnd)
{
  xcb_query_tree_reply_t *reply = xcb_query_tree_reply(mConn, xcb_query_tree(mConn, wnd), NULL);
  if(reply){
    xcb_window_t root = reply->root;
    free(reply);
    const xcb_setup_t *setup = xcb_get_setup(mConn);
    int32_t screen_count = xcb_setup_roots_length(setup);
    xcb_screen_iterator_t iter = xcb_setup_roots_iterator(setup);
    for(int i = 0; i < screen_count; ++i) {
      if(iter.data->root == root){
        return i;
      }
      xcb_screen_next(&iter);
    }
  }
  return -1;
}

bool XcbPlatform::CheckScreenIsTrueColor(int screen) const
{
    int vid = mScreens[screen]->root_visual;

    xcb_visualtype_t* vt = nullptr;
    xcb_depth_iterator_t dit = xcb_screen_allowed_depths_iterator(mScreens[screen]);
    for (; dit.rem && !vt; xcb_depth_next(&dit)) {
        xcb_visualtype_iterator_t vit = xcb_depth_visuals_iterator(dit.data);
        for(; vit.rem; xcb_visualtype_next(&vit)) {
            if(vid == vit.data->visual_id){
                vt = vit.data;
                break;
            }
        }
    }
    // we couldn't find the visualtype, so assume false
    return vt && (vt->_class == XCB_VISUAL_CLASS_TRUE_COLOR)
        && (vt->red_mask == 0xff0000) && (vt->green_mask == 0xff00) && (vt->blue_mask == 0xff);
}

bool XcbPlatform::MoveCursor(RealWindow* wnd, MouseMoveMode mode, int cx, int cy)
{
  int screenIx = WindowToScreen(wnd->mWnd);
  xcb_screen_t* screen = mScreens[screenIx];
  xcb_void_cookie_t ck;
  int16_t cx16 = (int16_t)cx;
  int16_t cy16 = (int16_t)cy;
  if (mode == MOUSE_MOVE_WINDOW)
  {
    // Get the window position relative to the screen root.
    xcb_rectangle_t re = wnd->GetBounds();
    ck = xcb_warp_pointer_checked(mConn, XCB_NONE, screen->root, 0, 0, 0, 0, re.x + cx16, re.y + cy16);
  }
  else if (mode == MOUSE_MOVE_RELATIVE)
  {
    ck = xcb_warp_pointer_checked(mConn, XCB_NONE, XCB_NONE, 0, 0, 0, 0, cx16, cy16);
  }
  else if (mode == MOUSE_MOVE_SCREEN)
  {
    ck = xcb_warp_pointer_checked(mConn, XCB_NONE, screen->root, 0, 0, 0, 0, cx16, cy16);
  }
  xcb_generic_error_t* err = xcb_request_check(mConn, ck);
  if (err)
  {
    char msg[XERR_MSG_SIZE];
    XGetErrorText(dpy, err->error_code, msg, XERR_MSG_SIZE);
    TRACE("PX11:MoveCursor: error %s\n", msg);
    free(err);
    return false;
  }
  return true;
}

void XcbPlatform::ProcessXEvent(xcb_generic_event_t* evt)
{
#define LOG_PREFIX "PX11:Platform:ProcessXEvent"
  if (!evt) {
    return;
  }

  // The target window for this event, if applicable.
  // Updated by each event type accordingly.
  xcb_window_t destWnd = 0;

  switch(evt->response_type & ~0x80) {
    case 0:
    {
      // type 0 means error
      auto err = (xcb_value_error_t*) evt;
      TRACE(LOG_PREFIX ":XCB ERROR: code %d, sequence %d, value %d, opcode %d:%d\n",
        err->error_code, err->sequence, err->bad_value, err->minor_opcode, err->major_opcode);
      break;
    }

    // These are all window events with the same general layout,
    // so we can grab the window ID the same way from all of them.
    case XCB_EXPOSE:
    case XCB_MAP_NOTIFY:
    case XCB_UNMAP_NOTIFY:
    case XCB_CONFIGURE_NOTIFY:
    case XCB_REPARENT_NOTIFY:
    case XCB_CLIENT_MESSAGE: {
      auto e = (xcb_configure_notify_event_t*)evt;
      // double-check that it's actually for the correct window
      if (e->event == e->window) {
        destWnd = e->window;
      }
      break;
    }
    // These all have the window as the "event" field.
    case XCB_MOTION_NOTIFY:
    case XCB_ENTER_NOTIFY:
    case XCB_LEAVE_NOTIFY:
    case XCB_KEY_PRESS:
    case XCB_KEY_RELEASE:
    case XCB_BUTTON_PRESS:
    case XCB_BUTTON_RELEASE: {
      auto e = (xcb_enter_notify_event_t*)evt;
      destWnd = e->event;
      break;
    }

    case XCB_PROPERTY_NOTIFY: {
      auto e = (xcb_property_notify_event_t*) evt;
      destWnd = e->window;
      // This is another way in which we can receive clipboard data.
      // Maybe because of Xwayland?
      if (e->atom == catoms[ATOM_CLIPBOARD]) {
        // TODO receive clipboard
        // xcbt_receive_clipboard(xw, XCBT_ATOM_CLIPBOARD(x));
      }
      break;
    }
    case XCB_SELECTION_CLEAR: {
      // A window has been asked to not be the clipboard owner anymore.
      // We don't always receive this event, maybe due to Xwayland or XEmbed?
      auto e = (xcb_selection_clear_event_t*) evt;
      if (e->owner != mClipboardOwner) {
        mClipboardOwner = 0;
        mClipboardData.clear();
      }
      // TODO Now we want to know who the new owner is.
      break;
    }
    case XCB_SELECTION_REQUEST: {
      // This is clipboard-related request
      xcb_selection_request_event_t* e = (xcb_selection_request_event_t*) evt;
      if (e->property == XCB_NONE) {
        e->property = e->target;
      }

      bool valid = true;
      if (e->target == catoms[ATOM_UTF8_STRING]
          || e->target == catoms[ATOM_STRING]
          || e->target == catoms[ATOM_TEXT]) {
        // Request clipboard contents
        ReplaceProperty(
          e->requestor, e->property, e->target, 8, mClipboardData.size(), mClipboardData.data());
      }
      else if (e->target == catoms[ATOM_TARGETS]) {
        // Request to see what type of targets we support
        xcb_atom_t targets[] = {
          catoms[ATOM_TARGETS],
          catoms[ATOM_UTF8_STRING],
          catoms[ATOM_STRING],
          catoms[ATOM_TEXT],
        };
        ReplaceProperty(
          // window, property, type
          e->requestor, e->property, XCB_ATOM_ATOM,
          // format
          sizeof(xcb_atom_t) * 8,
          // size, data
          sizeof(targets) / sizeof(xcb_atom_t), targets);
      } else {
        // not a request we can process
        valid = false;
      }

      xcb_selection_notify_event_t notify = {0};
      notify.response_type = XCB_SELECTION_NOTIFY;
      notify.time = XCB_CURRENT_TIME;
      notify.requestor = e->requestor;
      notify.selection = e->selection;
      notify.target = e->target;
      notify.property = valid ? e->property : XCB_NONE;
      xcb_send_event(mConn, 0, e->requestor, XCB_EVENT_MASK_PROPERTY_CHANGE, (char*)&notify);
      xcb_flush(mConn);
      break;
    }
    case XCB_SELECTION_NOTIFY: {
      // We requested clipoard data and it has arrived.
      // For now we assume the data is in the format requested, but potentially it's not?
      // Not sure what to do with that yet.
      auto e = (xcb_selection_notify_event_t*) evt;
      if (e->selection == catoms[ATOM_CLIPBOARD] && e->property != XCB_NONE) {
        xcb_icccm_get_text_property_reply_t prop;
        xcb_get_property_cookie_t cookie =
            xcb_icccm_get_text_property(mConn, e->requestor, e->property);

        if (xcb_icccm_get_text_property_reply(mConn, cookie, &prop, NULL)) {
          // resize clipboard data and copy it
          mClipboardData.resize(prop.name_len + 1);
          memcpy(mClipboardData.data(), prop.name, prop.name_len);
          // ensure we have a null-terminator
          mClipboardData[prop.name_len] = 0;
          // Wipe the property and then delete it. Not sure why deleting is
          // required, but that's what the examples I've seen do.
          xcb_icccm_get_text_property_reply_wipe(&prop);
          xcb_delete_property(mConn, e->requestor, e->property);
        } else {
          TRACE(LOG_PREFIX ": failed to get clipboard reply\n");
        }
      }
      break;
    }
    default:
      TRACE(LOG_PREFIX ": Event %d (%s)\n", evt->response_type & ~0x80, evt->response_type & 0x80 ? "Synthetic" : "Native");
      return;
  }

  for (unsigned i = 0; i < mWindows.size(); i++) {
    auto wnd = mWindows[i];
    if (wnd->mWnd == destWnd) {
      wnd->ProcessXEvent(evt);
      break;
    }
  }
#undef LOG_PREFIX
}

void XcbPlatform::ProcessEventQueue()
{
  xcb_generic_event_t* evt;
  xcb_flush(mConn);
  while((evt = xcb_poll_for_event(mConn))) {
    ProcessXEvent(evt);
    free(evt);
  }
}

bool XcbPlatform::CheckCookie(xcb_void_cookie_t ck, const char* prefix) const
{
#ifdef NDEBUG
  (void)prefix;
  xcb_generic_error_t* err = xcb_request_check(mConn, ck);
  if (err) {
    free(err);
    return true;
  }
  return false;
#else
  char msgbuf[XERR_MSG_SIZE];
  xcb_generic_error_t* err = xcb_request_check(mConn, ck);
  if (err)
  {
    XGetErrorText(dpy, err->error_code, msgbuf, sizeof(msgbuf));
    TRACE("%s:XCB: %s\n", prefix, msgbuf);
    free(err);
    return true;
  }
  return false;
#endif
}

#pragma endregion XcbImpl

//---------------------------//
// RealWindow Implementation //
//---------------------------//
#pragma region RealWindow

RealWindow::RealWindow(XcbPlatform* xp)
: mWnd(0)
, mCmap(0)
, mGc(0)
, mGlWindow(0)
, mGlContext(nullptr)
, mInDraw(0)
, mVisible(false)
{
  mPlatform = reinterpret_cast<PlatformX11*>(xp);
}

RealWindow::~RealWindow()
{
  Destroy();
}

bool RealWindow::Create(const WindowOptions& options, int visual_id)
{
  uint32_t eventmask =
    XCB_EVENT_MASK_EXPOSURE | // we want to know when we need to redraw
    XCB_EVENT_MASK_STRUCTURE_NOTIFY | // get varius notification messages like configure, reparent, etc.
    XCB_EVENT_MASK_PROPERTY_CHANGE | // useful when something will change our property
    XCB_EVENT_MASK_BUTTON_PRESS | XCB_EVENT_MASK_BUTTON_RELEASE  |  // mouse clicks
    XCB_EVENT_MASK_KEY_PRESS | XCB_EVENT_MASK_KEY_RELEASE  |      // keyboard is questionable accordung to XEMBED
    XCB_EVENT_MASK_ENTER_WINDOW   | XCB_EVENT_MASK_LEAVE_WINDOW |   // mouse entering/leaving
    XCB_EVENT_MASK_POINTER_MOTION // mouse motion
    ;

  const auto xp = CastX();
  char errbuf[XERR_MSG_SIZE];

  bool hasCmap = !(options.flags & XcbPlatform::NO_COLORMAP);
  xcb_generic_error_t* err = nullptr;

  mWnd = xcb_generate_id(conn());
  // create a colormap only if parent is not 0
  mCmap = hasCmap ? xcb_generate_id(conn()) : 0;
  // unknown what this means
  uint32_t wa[] = { eventmask, mCmap, 0 };
  // window's value mask.
  uint32_t value_mask = XCB_CW_EVENT_MASK | (hasCmap ? XCB_CW_COLORMAP : 0);

  if (hasCmap) {
    xcb_create_colormap(conn(), XCB_COLORMAP_ALLOC_NONE, mCmap, options.parent, visual_id);
  }
  xcb_rectangle_t bb = make_xrect(options.bounds);
  xcb_void_cookie_t create_ok = xcb_create_window_checked(
    conn(), XCB_COPY_FROM_PARENT, mWnd,
    options.parent, bb.x, bb.y, bb.width, bb.height, 0,
    XCB_WINDOW_CLASS_INPUT_OUTPUT, visual_id, value_mask, wa);
  err = xcb_request_check(conn(), create_ok);
  if (err)
  {
    XGetErrorText(xp->dpy, err->error_code, errbuf, sizeof(errbuf));
    TRACE("PX11:CreateWindow: xcb_create_window failed: %s\n", errbuf);
    return false;
  }

  // Window manager hints
  if (options.flags & XcbPlatform::WM_DECORATIONS) {
    xcb_atom_t wm_protocols[] = { xp->catoms[ATOM_WM_DELETE_WINDOW] };
    xp->ReplaceProperty(mWnd, xp->catoms[ATOM_WM_PROTOCOLS], XCB_ATOM_ATOM, 32, 1, wm_protocols);
  }

  // enable embedding by default


  return true;
}

void RealWindow::Destroy()
{
  auto xp = CastX();
  if (mGlContext) {
    if (glXGetCurrentContext() == mGlContext) {
      // Set the context to not be the one we're about to destroy
      glXMakeContextCurrent(xp->dpy, 0, 0, nullptr);
    }
    glXDestroyContext(xp->dpy, mGlContext);
    mGlContext = nullptr;
  }
  if (mGlWindow) {
    glXDestroyWindow(xp->dpy, mGlWindow);
    mGlWindow = 0;
  }
  if (mWnd) {
    xcb_destroy_window(conn(), mWnd);
    mWnd = 0;
  }
  if (mCmap) {
    xcb_free_colormap(conn(), mCmap);
    mCmap = 0;
  }
  if (mGc) {
    xcb_free_gc(conn(), mGc);
    mGc = 0;
  }
  // Remove self from list of known windows
  auto self = this;
  std::remove_if(xp->mWindows.begin(), xp->mWindows.end(), [&](auto w) { return w == self; });
}

bool RealWindow::DrawBegin()
{
#define LOG_PREFIX "PX11:Window:DrawBegin"
  auto xp = CastX();
  mInDraw++;
  if (mInDraw == 1 && mGlContext) {
    if (!glXMakeContextCurrent(xp->dpy, mGlWindow, mGlWindow, mGlContext)) {
      TRACE(LOG_PREFIX ":BUG: glXMakeContextCurrent failed\n");
      return false;
    }
  }
  if (mInDraw > 1 && mGlContext) {
    GLXContext old = glXGetCurrentContext();
    if (old != mGlContext) {
      TRACE(LOG_PREFIX ":BUG: reentrant draw, but different GL context\n");
      return false;
    }
  }
  return true;
#undef LOG_PREFIX
}

void RealWindow::DrawEnd()
{
#define LOG_PREFIX "PX11:Window:DrawEnd"
  if (mInDraw > 0) {
    mInDraw--;
    if (mInDraw == 0 && mGlContext) {
      // Swap buffers
      glXSwapBuffers(CastX()->dpy, mGlWindow);
      // Unset the context. IMPORTANT!! If we don't do this every time, then
      // we can't render off-thread which causes problems.
      glXMakeContextCurrent(CastX()->dpy, 0, 0, nullptr);
    }
  } else {
    TRACE(LOG_PREFIX ":BUG: draw end without begin\n");
  }
#undef LOG_PREFIX
}

void RealWindow::SetTitle(const char* title)
{
    size_t title_len = strlen(title);
    CastX()->ReplaceProperty(mWnd, XCB_ATOM_WM_NAME, XCB_ATOM_STRING, 8, title_len, title);
    CastX()->ReplaceProperty(mWnd, XCB_ATOM_WM_ICON_NAME, XCB_ATOM_STRING, 8, title_len, title);
}

void RealWindow::SetVisible(bool show)
{
    // if there's nothing to do, skip
    if (show == this->mVisible) {
      return;
    }
    if (show) {
      xcb_map_window(conn(), mWnd);
    } else {
      xcb_unmap_window(conn(), mWnd);
    }
    this->mVisible = show;
}

void RealWindow::EnableEmbed(bool on)
{
  auto xp = CastX();
  if (on) {
    // fields: version, flags
    // version is always 0, flags is a bitmask
    uint32_t info[] = { 0, 0 }; // version 0, not mapped
    if (mVisible) {
      // request to be visible
      info[1] |= XEMBED_MAPPED;
    }
    xp->ReplaceProperty(mWnd, xp->catoms[ATOM_XEMBED_INFO], xp->catoms[ATOM_XEMBED_INFO], 32, 2, info);
  } else {
    xcb_delete_property(conn(), mWnd, xp->catoms[ATOM_XEMBED_INFO]);
  }
}

xcb_rectangle_t RealWindow::GetBounds()
{
  xcb_rectangle_t bb {0, 0, 0, 0};

  // Get the window position relative to the screen root.
  xcb_query_tree_cookie_t cookie1 = xcb_query_tree(conn(), mWnd);
  xcb_query_tree_reply_t* tree = xcb_query_tree_reply(conn(), cookie1, NULL);
  if (!tree) {
    return bb;
  }
  // TODO finish
  return mBounds;
#if 0
  xcb_translate_coordinates_cookie_t cookie2 = xcb_translate_coordinates(
      conn(), mWnd, tree->root, xw->pos.x, xw->pos.y);
  xcb_translate_coordinates_reply_t* trans = xcb_translate_coordinates_reply(x->conn, cookie2, NULL);
  if (!trans) {
    free(tree);
    return;
  }

  rect->x = trans->dst_x;
  rect->y = trans->dst_y;
  free(tree);
  free(trans);
#endif
}

bool RealWindow::DrawImage(const WRect& area, int format, const uint8_t* data)
{
  if (format != kPF_RGBA8) {
    return false;
  }
  xcb_rectangle_t bounds = make_xrect(area);
  unsigned dataLen = area.w * area.h * 4;
  unsigned depth = CastX()->GetScreen(0)->root_depth;
  return PutPixels(bounds, depth, dataLen, data);
}

bool RealWindow::PutPixels(const xcb_rectangle_t& bounds, unsigned depth, unsigned data_length, const uint8_t* data)
{
#define LOG_PREFIX "PX11:Window:DrawImage"
  // no reason we can't, but better to not allow bugs to creep in.
  if (!mInDraw) {
    TRACE(LOG_PREFIX ":BUG: call to PutPixels outside of DrawBegin()/DrawEnd()\n");
    return false;
  }

  auto xp = CastX();

  // create a gcontext on-demand
  if (!mGc) {
    xcb_gcontext_t gc = xcb_generate_id(conn());
    xcb_screen_t *si = xp->GetScreen(mScreen);
    if (si) {
      uint32_t value_list[2] = { si->white_pixel, si->black_pixel };
      auto ck = xcb_create_gc_checked(conn(), gc, mWnd, XCB_GC_FOREGROUND | XCB_GC_BACKGROUND, value_list);
      if (xp->CheckCookie(ck, LOG_PREFIX)) {
        mGc = 0;
        return false;
      }
    } else {
      TRACE(LOG_PREFIX ":BUG: Window not on a known screen\n");
      return false;
    }
  }

  // We know mGc is valid now, or we would have returned earlier.
  // Don't check the error here, let the event handler deal with it.
  // If this image doesn't get rendered, we can just fail later.
  xcb_put_image(
    conn(), XCB_IMAGE_FORMAT_Z_PIXMAP, mWnd, mGc,
    bounds.width, bounds.height, bounds.x, bounds.y, 0, depth, data_length, data);

  return true;

#undef LOG_PREFIX
}

void RealWindow::ProcessXEvent(xcb_generic_event_t* evt)
{
#define LOG_PREFIX "PX11:Window:ProcessXEvent"
  if (!evt) {
    return;
  }

  // Event to be appended to the queue, if type is not 0.
  SDL_Event qevent;
  qevent.type = 0;

  auto xp = CastX();
  uint8_t type = evt->response_type & ~0x80;
  switch(type) {

    // Key press and release
    case XCB_KEY_PRESS:
    case XCB_KEY_RELEASE:
    {
      using iplug::EVirtualKey;
      auto kp = (xcb_key_press_event_t*) evt;

      bool isDown = type == XCB_KEY_PRESS;
      EVirtualKey vk = KeyboardDetailToVirtualKey(kp->detail);

      // Update the global internal state
      if (vk == EVirtualKey::kVK_SHIFT) {
        xp->mShiftDown = isDown;
      } else if (vk == EVirtualKey::kVK_CONTROL) {
        xp->mCtrlDown = isDown;
      } else if (vk == EVirtualKey::kVK_MENU) {
        xp->mAltDown = isDown;
      }

      #if 0
      // use Xlib to lookup the key event information
      XKeyEvent keyev;
      keyev.display = dpy;
      keyev.keycode = kp->detail;
      keyev.state = kp->state;
      char buf[16]{};
      KeySym keysym;
      if (XLookupString(&keyev, buf, sizeof(buf), &keysym, nullptr)) {
      }
      #endif

      qevent.type = isDown ? SDL_EVENT_KEY_DOWN : SDL_EVENT_KEY_UP;
      qevent.key.down = isDown;
      qevent.key.key = vk;
      qevent.key.windowID = mWnd;
      qevent.key.mod = kp->state;
      qevent.key.repeat = false;
      break;
    }

    case XCB_BUTTON_PRESS:
    case XCB_BUTTON_RELEASE:
    {
      auto e = (xcb_button_press_event_t*) evt;
      int btn = e->detail;
      bool isDown = e->response_type == XCB_BUTTON_PRESS;

      // 1 = left click, 2 = middle click, 3 = right click
      if (btn == 1 || btn == 2 || btn == 3) {
        // most of the event fields are the same
        qevent.type = SDL_EVENT_MOUSE_BUTTON_DOWN;
        qevent.button.clicks = 1;
        qevent.button.down = isDown;
        qevent.button.which = 0;
        qevent.button.windowID = mWnd;
        qevent.button.x = e->event_x;
        qevent.button.y = e->event_y;

        if (btn == 1) {
          qevent.button.button = SDL_BUTTON_LEFT;

          // special handling for double-click
          if (isDown && (e->time - mLastLeftClickStamp) < xp->mDblClickTimeout) {
            qevent.button.clicks = 2;
            // reset so we don't spam double-click events accidentally
            mLastLeftClickStamp = 0;
          } else {
            mLastLeftClickStamp = e->time;
          }
        } else if (btn == 2) {
          qevent.button.button = SDL_BUTTON_MIDDLE;
        } else if (btn == 3) {
          qevent.button.button = SDL_BUTTON_RIGHT;
        }
      }

      // 4 = wheel up, 5 = wheel down
      // Also, we don't care about wheel release events.
      if (isDown && (btn == 4 || btn == 5)) {
        qevent.type = SDL_EVENT_MOUSE_WHEEL;
        qevent.wheel.which = 0;
        qevent.wheel.windowID = mWnd;
        qevent.wheel.mouse_x = e->event_x;
        qevent.wheel.mouse_y = e->event_y;
        qevent.wheel.direction = SDL_MOUSEWHEEL_NORMAL;
        qevent.wheel.x = 0;
        qevent.wheel.y = (btn == 4) ? 1.f : -1.f;
      }
      break;
    }

    case XCB_MOTION_NOTIFY:
    {
      auto e = (xcb_motion_notify_event_t*) evt;

      // has to be coming from the same screen
      if (!e->same_screen) {
        break;
      }

      // Don't send events for the cursor being at the locked position.
      // If we do, then any "delta" movement will just go back to where it was.
      if (mCursorLock && e->event_x == mLock.x && e->event_y == mLock.y) {
        break;
      }

      qevent.type = SDL_EVENT_MOUSE_MOTION;
      qevent.motion.state = 0
        | (e->state & XCB_BUTTON_MASK_1 ? SDL_BUTTON_LMASK : 0)
        | (e->state & XCB_BUTTON_MASK_2 ? SDL_BUTTON_MMASK : 0)
        | (e->state & XCB_BUTTON_MASK_3 ? SDL_BUTTON_RMASK : 0);
      qevent.motion.which = 0;
      qevent.motion.windowID = mWnd;
      qevent.motion.x = (float)e->event_x;
      qevent.motion.y = (float)e->event_y;
      qevent.motion.xrel = (float)(e->event_x - mCursorPos.x);
      qevent.motion.yrel = (float)(e->event_y - mCursorPos.y);

      if (mCursorLock) {
        // Reset mouse position back to lock
        xp->MoveCursor(this, XcbPlatform::MOUSE_MOVE_WINDOW, mLock.x, mLock.y);
      } else {
        // Update known cursor position
        mCursorPos.x = e->event_x;
        mCursorPos.y = e->event_y;
      }
      break;
    }

    case XCB_ENTER_NOTIFY:
    {
      qevent.type = SDL_EVENT_WINDOW_MOUSE_ENTER;
      qevent.window.windowID = mWnd;
      break;
    }
    case XCB_LEAVE_NOTIFY:
    {
      qevent.type = SDL_EVENT_WINDOW_MOUSE_LEAVE;
      qevent.window.windowID = mWnd;
      break;
    }
    case XCB_FOCUS_IN:
    {
      qevent.type = SDL_EVENT_WINDOW_FOCUS_GAINED;
      qevent.window.windowID = mWnd;
      break;
    }
    case XCB_FOCUS_OUT:
    {
      qevent.type = SDL_EVENT_WINDOW_FOCUS_LOST;
      qevent.window.windowID = mWnd;
      break;
    }

    case XCB_EXPOSE:
    {
      auto e = (xcb_expose_event_t *)evt;
      // MAYBE: can collect and use invalidated areas
      // If this is more than 0, then it's multiple invalid areas. For now,
      // just assume the whole UI is invalid if we get an expose request.
      if (e->count == 0)
      {
        qevent.type = SDL_EVENT_WINDOW_EXPOSED;
        qevent.window.windowID = mWnd;
      }
      break;
    }

    case XCB_MAP_NOTIFY:
    {
      xcb_map_notify_event_t *mn = (xcb_map_notify_event_t *)evt;
      if(mn->event != mn->window) {
        break;
      }
      if (!mVisible) {
        mVisible = true;
        qevent.type = SDL_EVENT_WINDOW_SHOWN;
        qevent.window.windowID = mWnd;
      }
      break;
    }
    case XCB_UNMAP_NOTIFY:
    {
      xcb_unmap_notify_event_t *mn = (xcb_unmap_notify_event_t *)evt;
      if(mn->event != mn->window) {
        break;
      }
      if (mVisible) {
        mVisible = false;
        qevent.type = SDL_EVENT_WINDOW_HIDDEN;
        qevent.window.windowID = mWnd;
      }
      break;
    }

    case XCB_REPARENT_NOTIFY:
      break;

    case XCB_CONFIGURE_NOTIFY:
    {
      auto e = (xcb_configure_notify_event_t *)evt;
      if(e->event != e->window) {
        break;
      }

      // ignore synthetic, they are from WM about screen position
      if( !(evt->response_type & 0x80) ) {
        if((e->width != mBounds.width) || (e->height != mBounds.height)){
          TRACE("Size is changed to %ux%u\n", e->width, e->height);
          mBounds.width = e->width;
          mBounds.height = e->height;

          // create event and add it to the queue to notify the client
          SDL_Event ev1;
          ev1.type = SDL_EVENT_WINDOW_RESIZED;
          ev1.window.windowID = mWnd;
          ev1.window.data1 = mBounds.width;
          ev1.window.data2 = mBounds.height;
          mEvents.push_back(ev1);
        }

        if (e->x != mBounds.x || e->y != mBounds.y) {
          mBounds.x = e->x;
          mBounds.y = e->y;

          // create event and add it to queue to notify client
          SDL_Event ev1;
          ev1.type = SDL_EVENT_WINDOW_MOVED;
          ev1.window.windowID = mWnd;
          ev1.window.data1 = mBounds.x;
          ev1.window.data2 = mBounds.y;
          mEvents.push_back(ev1);
        }
      }
      break;
    }

    case XCB_PROPERTY_NOTIFY:
    {
      auto e = (xcb_property_notify_event_t*) evt;
      xcb_atom_t atomXEMBED = xp->catoms[ATOM_XEMBED_INFO];
      if (e->atom == atomXEMBED) {
        // This indicates we need to change mapping status.
        // Just to be sure, let's get _XEMBED_INFO and check.
        auto prop = GetProperty(xp, mWnd, atomXEMBED, atomXEMBED, 0, 2);
        if (!prop) {
          // Failed to get property somehow!? Oh well, just map it anways.
          SetVisible(true);
          break;
        }
        auto embedInfo = (uint32_t*)xcb_get_property_value(prop);
        SetVisible((embedInfo[1] & XEMBED_MAPPED) != 0);
        free(prop);
      }
      break;
    }

    case XCB_CLIENT_MESSAGE:
    {

      auto e = (xcb_client_message_event_t*) evt;
      if (e->type == xp->catoms[ATOM_XEMBED]) {
        // TODO: process different xembed messages
        uint32_t op = e->data.data32[1];
        TRACE("Received _XEMBED message opcode: %u\n", op);
      }
      break;
    }
  }

#undef LOG_PREFIX
}

bool RealWindow::PollEvent(SDL_Event* event)
{
  if (mEvents.empty()) {
    return false;
  }
  *event = mEvents.front();
  mEvents.pop_front();
  return true;
}

#pragma endregion RealWindow

//----------------------------------//
// Implementation of the public API //
//----------------------------------//

#pragma region Public implementation


PlatformX11* PlatformX11::Create()
{
  // make sure that, if someone DOES accidentally copy the PlatformX11,
  // that it copies the whole thing, not just part of it. Then it should
  // crash more reasonably, instead of weirdly.
  static_assert(sizeof(PlatformX11) >= sizeof(XcbPlatform));

  XcbPlatform* xp = new XcbPlatform();
  xp->Connect();
  if (!(xp->mStatus & XcbPlatform::kSuccess)) {
    delete xp;
    return nullptr;
  }
  return reinterpret_cast<PlatformX11*>(xp);
}

#define PSELF reinterpret_cast<XcbPlatform*>(this)

// dummy constructor
PlatformX11::PlatformX11() {}
PlatformX11::~PlatformX11()
{
  PSELF->~XcbPlatform();
}

X11Window* PlatformX11::CreateWindow(const WindowOptions& options)
{
  return reinterpret_cast<X11Window*>(PSELF->CreateWindow(options));
}

void PlatformX11::ProcessEvents()
{
  PSELF->ProcessEventQueue();
}


#undef PSELF

#define PSELF reinterpret_cast<RealWindow*>(this)
#define PCSELF reinterpret_cast<const RealWindow*>(this)

void X11Window::Close()
{
  // have to cast to RealWindow for delete, otherwise it won't delete correctly.
  delete PSELF;
}

bool X11Window::DrawBegin()
{ return PSELF->DrawBegin(); }

void X11Window::DrawEnd()
{ PSELF->DrawEnd(); }

bool X11Window::DrawImage(const WRect& bounds, int format, const uint8_t* data)
{ return PSELF->DrawImage(bounds, format, data); }

void X11Window::SetVisible(bool show)
{ PSELF->SetVisible(show); }

bool X11Window::IsVisible() const
{ return PCSELF->mVisible; }

void X11Window::SetTitle(const char* title)
{ PSELF->SetTitle(title); }

bool X11Window::PollEvent(SDL_Event* event)
{ return PSELF->PollEvent(event); }

#pragma endregion Public implementation


#pragma region KeyMap

iplug::EVirtualKey KeyboardDetailToVirtualKey(unsigned int keysym) {
  // TODO(sad): Have |keysym| go through the X map list?
  using EK = iplug::EVirtualKey;
  // [a-z] cases.
  if (keysym >= XK_a && keysym <= XK_z)
    return static_cast<EK>(EK::kVK_A + keysym - XK_a);
  // [0-9] cases.
  if (keysym >= XK_0 && keysym <= XK_9)
    return static_cast<EK>(EK::kVK_0 + keysym - XK_0);

  switch (keysym) {
    case XK_BackSpace:
      return EK::kVK_BACK;
    case XK_Delete:
    case XK_KP_Delete:
      return EK::kVK_DELETE;
    case XK_Tab:
    case XK_KP_Tab:
    case XK_ISO_Left_Tab:
    case XK_3270_BackTab:
      return EK::kVK_TAB;
    case XK_Linefeed:
    case XK_Return:
    case XK_KP_Enter:
    case XK_ISO_Enter:
      return EK::kVK_RETURN;
    case XK_Clear:
    case XK_KP_Begin:  // NumPad 5 without Num Lock, for crosbug.com/29169.
      return EK::kVK_CLEAR;
    case XK_KP_Space:
    case XK_space:
      return EK::kVK_SPACE;
    case XK_Home:
    case XK_KP_Home:
      return EK::kVK_HOME;
    case XK_End:
    case XK_KP_End:
      return EK::kVK_END;
    case XK_Page_Up:
    case XK_KP_Page_Up:  // aka XK_KP_Prior
      return EK::kVK_PRIOR;
    case XK_Page_Down:
    case XK_KP_Page_Down:  // aka XK_KP_Next
      return EK::kVK_NEXT;
    case XK_Left:
    case XK_KP_Left:
      return EK::kVK_LEFT;
    case XK_Right:
    case XK_KP_Right:
      return EK::kVK_RIGHT;
    case XK_Down:
    case XK_KP_Down:
      return EK::kVK_DOWN;
    case XK_Up:
    case XK_KP_Up:
      return EK::kVK_UP;
    case XK_Escape:
      return EK::kVK_ESCAPE;
    case XK_Kana_Lock:
    case XK_Kana_Shift:
      return EK::kVK_KANA;
    case XK_Hangul:
      return EK::kVK_HANGUL;
    case XK_Hangul_Hanja:
      return EK::kVK_HANJA;
    case XK_Kanji:
      return EK::kVK_KANJI;
    case XK_Henkan:
      return EK::kVK_CONVERT;
    case XK_Muhenkan:
      return EK::kVK_NONCONVERT;
    // Unimplemented, no matching key code on Windows
    // case XK_Zenkaku_Hankaku:
    //   return EK::kVK_DBE_DBCSCHAR;
    case XK_KP_0:
    case XK_KP_1:
    case XK_KP_2:
    case XK_KP_3:
    case XK_KP_4:
    case XK_KP_5:
    case XK_KP_6:
    case XK_KP_7:
    case XK_KP_8:
    case XK_KP_9:
      return static_cast<EK>(EK::kVK_NUMPAD0 + (keysym - XK_KP_0));
    case XK_multiply:
    case XK_KP_Multiply:
      return EK::kVK_MULTIPLY;
    case XK_KP_Add:
      return EK::kVK_ADD;
    case XK_KP_Separator:
      return EK::kVK_SEPARATOR;
    case XK_KP_Subtract:
      return EK::kVK_SUBTRACT;
    case XK_KP_Decimal:
      return EK::kVK_DECIMAL;
    case XK_KP_Divide:
      return EK::kVK_DIVIDE;
    case XK_KP_Equal:
    case XK_equal:
    case XK_plus:
      return EK::kVK_OEM_PLUS;
    case XK_comma:
    case XK_less:
      return EK::kVK_OEM_COMMA;
    case XK_minus:
    case XK_underscore:
      return EK::kVK_OEM_MINUS;
    case XK_greater:
    case XK_period:
      return EK::kVK_OEM_PERIOD;
    case XK_colon:
    case XK_semicolon:
      return EK::kVK_OEM_1;
    case XK_question:
    case XK_slash:
      return EK::kVK_OEM_2;
    case XK_asciitilde:
    case XK_quoteleft:
      return EK::kVK_OEM_3;
    case XK_bracketleft:
    case XK_braceleft:
      return EK::kVK_OEM_4;
    case XK_backslash:
    case XK_bar:
      return EK::kVK_OEM_5;
    case XK_bracketright:
    case XK_braceright:
      return EK::kVK_OEM_6;
    case XK_quoteright:
    case XK_quotedbl:
      return EK::kVK_OEM_7;
    case XK_ISO_Level5_Shift:
      return EK::kVK_OEM_8;
    case XK_Shift_L:
    case XK_Shift_R:
      return EK::kVK_SHIFT;
    case XK_Control_L:
    case XK_Control_R:
      return EK::kVK_CONTROL;
    case XK_Meta_L:
    case XK_Meta_R:
    case XK_Alt_L:
    case XK_Alt_R:
      return EK::kVK_MENU;
    case XK_ISO_Level3_Shift:
    case XK_Mode_switch:
      return EK::kVK_ALTGR;
    case XK_Multi_key:
      return EK::kVK_COMPOSE;
    case XK_Pause:
      return EK::kVK_PAUSE;
    case XK_Caps_Lock:
      return EK::kVK_CAPITAL;
    case XK_Num_Lock:
      return EK::kVK_NUMLOCK;
    case XK_Scroll_Lock:
      return EK::kVK_SCROLL;
    case XK_Select:
      return EK::kVK_SELECT;
    case XK_Print:
      return EK::kVK_PRINT;
    case XK_Execute:
      return EK::kVK_EXECUTE;
    case XK_Insert:
    case XK_KP_Insert:
      return EK::kVK_INSERT;
    case XK_Help:
      return EK::kVK_HELP;
    case XK_Super_L:
      return EK::kVK_LWIN;
    case XK_Super_R:
      return EK::kVK_RWIN;
    case XK_Menu:
      return EK::kVK_APPS;
    case XK_F1:
    case XK_F2:
    case XK_F3:
    case XK_F4:
    case XK_F5:
    case XK_F6:
    case XK_F7:
    case XK_F8:
    case XK_F9:
    case XK_F10:
    case XK_F11:
    case XK_F12:
    case XK_F13:
    case XK_F14:
    case XK_F15:
    case XK_F16:
    case XK_F17:
    case XK_F18:
    case XK_F19:
    case XK_F20:
    case XK_F21:
    case XK_F22:
    case XK_F23:
    case XK_F24:
      return static_cast<EK>(EK::kVK_F1 + (keysym - XK_F1));
    case XK_KP_F1:
    case XK_KP_F2:
    case XK_KP_F3:
    case XK_KP_F4:
      return static_cast<EK>(EK::kVK_F1 + (keysym - XK_KP_F1));
    case XK_guillemotleft:
    case XK_guillemotright:
    case XK_degree:
    // In the case of canadian multilingual keyboard layout, VKEY_OEM_102 is
    // assigned to ugrave key.
    case XK_ugrave:
    case XK_Ugrave:
    case XK_brokenbar:
      return EK::kVK_OEM_102;  // international backslash key in 102 keyboard.
    // When evdev is in use, /usr/share/X11/xkb/symbols/inet maps F13-18 keys
    // to the special XF86XK symbols to support Microsoft Ergonomic keyboards:
    // https://bugs.freedesktop.org/show_bug.cgi?id=5783
    // In Chrome, we map these X key symbols back to F13-18 since we don't have
    // VKEYs for these XF86XK symbols.
    case XF86XK_Launch5:
      return EK::kVK_F14;
    case XF86XK_Launch6:
      return EK::kVK_F15;
    case XF86XK_Launch7:
      return EK::kVK_F16;
    case XF86XK_Launch8:
      return EK::kVK_F17;
    case XF86XK_Launch9:
      return EK::kVK_F18;
    // For supporting multimedia buttons on a USB keyboard.
    case XF86XK_Back:
      return EK::kVK_BROWSER_BACK;
    case XF86XK_Forward:
      return EK::kVK_BROWSER_FORWARD;
    case XF86XK_Reload:
      return EK::kVK_BROWSER_REFRESH;
    case XF86XK_Stop:
      return EK::kVK_BROWSER_STOP;
    case XF86XK_Search:
      return EK::kVK_BROWSER_SEARCH;
    case XF86XK_Favorites:
      return EK::kVK_BROWSER_FAVORITES;
    case XF86XK_HomePage:
      return EK::kVK_BROWSER_HOME;
    case XF86XK_AudioMute:
      return EK::kVK_VOLUME_MUTE;
    case XF86XK_AudioLowerVolume:
      return EK::kVK_VOLUME_DOWN;
    case XF86XK_AudioRaiseVolume:
      return EK::kVK_VOLUME_UP;
    case XF86XK_AudioNext:
      return EK::kVK_MEDIA_NEXT_TRACK;
    case XF86XK_AudioPrev:
      return EK::kVK_MEDIA_PREV_TRACK;
    case XF86XK_AudioStop:
      return EK::kVK_MEDIA_STOP;
    case XF86XK_AudioPlay:
      return EK::kVK_MEDIA_PLAY_PAUSE;
    case XF86XK_Mail:
      return EK::kVK_LAUNCH_MAIL;
    case XF86XK_LaunchA:  // F3 on an Apple keyboard.
      return EK::kVK_LAUNCH_APP1;
    case XF86XK_LaunchB:  // F4 on an Apple keyboard.
    case XF86XK_Calculator:
      return EK::kVK_LAUNCH_APP2;
    // XF86XK_Tools is generated from HID Usage AL_CONSUMER_CONTROL_CONFIG
    // (Usage 0x0183, Page 0x0C) and most commonly launches the OS default
    // media player (see crbug.com/398345).
    #if 0
    case XF86XK_Tools:
      return EK::kVK_MEDIA_LAUNCH_MEDIA_SELECT;
    case XF86XK_WLAN:
      return EK::kVK_WLAN;
    case XF86XK_PowerOff:
      return EK::kVK_POWER;
    case XF86XK_MonBrightnessDown:
      return EK::kVK_BRIGHTNESS_DOWN;
    case XF86XK_MonBrightnessUp:
      return EK::kVK_BRIGHTNESS_UP;
    case XF86XK_KbdBrightnessDown:
      return EK::kVK_KBD_BRIGHTNESS_DOWN;
    case XF86XK_KbdBrightnessUp:
      return EK::kVK_KBD_BRIGHTNESS_UP;
    #endif
   // TODO(sad): some keycodes are still missing.
  }
  return (EK)0;
}

#pragma endregion KeyMap
