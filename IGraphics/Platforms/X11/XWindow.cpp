#pragma once

#include <functional>
#include <mutex>
#include <atomic>
#include <unorderd_map>
#include <vector>
#include "IGraphicsStructs.h"

using iplug::igraphics::IRECT;

struct MouseEvent
{
    enum Type
    {
        kMouseNone = 0,
        kMouseDown = 1,
        kMouseUp = 2,
        kMouseMove = 3,
        kMouseScroll = 4,
    };

    Type type;
    float x;
    float y;
    float dx;
    float dy;
    float scroll;
    int button;
    int clicks;
};


class IWindowListener
{
public:
    virtual Paint(Window* window, const IRECT& area) = 0;
    virtual Resized(Window* window) = 0;
    virtual Moved(Window* window) = 0;
    virtual Visible(Window* window, bool visibile) = 0;
    virtual KeyDown(Window* window, int key) = 0;
    virtual KeyUp(Window* window, int key) = 0;
    virtual MouseEvent(Window* window, const MouseEvent& event) = 0;
};


typedef xcb_window_t XWindow;

struct GLConfig
{
    int versionMajor;
    int versionMinor;
    int redSize;
    int greenSize;
    int blueSize;
    int alphaSize;
    int depthSize;
    int stencilSize;
    bool doubleBuffer;
};

class XSys
{
public:
    static XSys* Instance()

    XWindow CreateWindow(xcb_window_t parent);
    void SetArea(XWindow win, const IRECT& area);
    void SetVisible(XWindow win, bool visible);
    void SetTitle(XWindow win, const char* title);
    void SetIcon(XWindow* win, const Image& image);
    void SetMousePosition(int x, int y);
    Vec2 GetMousePosition() const;

    GLXContext InitOpenGL(XWindow win, int glKind, int versionMajor, int versionMinor);

    void SetClipboardText(const char* text);
    void GetClipboardText(WDL_String& text_out);

    void ProcessEvent(xcb_generic_event* evt);

private:
    static std::mutex sCreateLock;
    static std::atomic<XSys*> sInstance;

    struct WindowData
    {
        xcb_window_t wnd;
        IRECT area;
        bool mapped;
        GLXContext glCtx;
        GLXDrawable glDraw;
        IWindowListener *listener;
    };

    inline xcb_connection_t* Conn() { return mConn; };

    std::unordered_map<XWindow, WindowData> mWindows;
    std::unordered_map<xcb_window_t, XWindow> mWindowsRev;
    std::vector<xcb_screen_t> mScreens;
    xcb_connection_t* mConn;
};


#include <unistd.h>
#include <sys/wait.h>


XSys* XSys::Instance()
{
    auto inst = sInstance.load(std::memory_order_acquire);
    if (!inst)
    {
        std::lock_guard<std::mutex> lock(sCreateLock);
        inst = sInstance.load(std::memory_order_acquire);
        if (inst)
        {
            return inst;
        }

        inst = new XSys();
        XSys* oldInst = nullptr;
        if (!sInstance.compare_exchange_strong(oldInst, newInst))
        {
            delete newInst;
        }
    }
    return inst;
}

void XSys::SetArea(XWindow win, const IRECT& area)
{
    auto wnd = mWindows.at(win);
    uint16_t mask = XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y
        | XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT;
    const uint32_t values[] = { static_cast<uint32_t>(area.L), static_cast<uint32_t>(area.T),
        static_cast<uint32_t>(area.W()), static_cast<uint32_t>(area.H()), };

    xcb_configure_window(Conn(), wnd.wnd, mask, values);
    xcb_flush(Conn());
}

void XSys::SetVisible(XWindow win, bool visible)
{
    auto wnd = mWindows.at(win);
    if (visible != wnd.mapped)
    {
        if (visible)
        {
            xcb_map_window(Conn(), win->mWnd);
        }
        else
        {
            xcb_unmap_window(Conn(), win->mWnd);
        }
        wnd.mapped = visible;
    }
}

void XSys::SetTitle(XWindow win, const char* title)
{
    auto wnd = mWindows.at(win);

    xcb_change_property(Conn(), XCB_PROP_MODE_REPLACE, wnd.wnd, XCB_ATOM_WM_NAME, XCB_ATOM_STRING, 8, strlen(title), title);
    xcb_flush(Conn());
}

void XSys::SetIcon(XWindow win, const Image& image)
{
    auto wnd = mWindows.at(win);

    // TODO implement icon set
}

void XSys::SetMousePosition(int x, int y)
{
    // TODO make this work on multiple screens
    //   Iterate through each screen to find (x,y) coordinates relative to (0,0) 
    //   This requires knowing screen positions relative to each other.
    xcb_screen_t* screen = mScreens[0];
    int16_t cx16 = (int16_t)cx;
    int16_t cy16 = (int16_t)cy;
    xcb_warp_pointer_checked(Conn(), XCB_NONE, screen->root, 0, 0, 0, 0, cx16, cy16);
    xcb_flush(Conn());
}

IVec2 XSys::GetMousePosition()
{
    // TODO 
}

GLXContext XSys::InitOpenGL(XWindow win, int glKind, int versionMajor, int versionMinor);
{
    GLXFBConfig *fbConfigs;
    int numConfigs;
    
    if((xw = (_xcbt_window *)calloc(1, sizeof(*xw)))){
    xw->x = x;
    xw->uhandler = (xcbt_window_handler)xcbt_window_default_handler;
    xw->x_prt  = prt;
    memcpy(&xw->pos, pos, sizeof(xcbt_rect));
    xw->screen = xcbt_xcb_window_screen(x, prt);
    int fbc_idx;
    if((xw->screen >= 0) && (fbcs = xcbt_window_gl_choose_fbconfig(xw, &fbc_idx))){
      XID vid;
      GLXFBConfig fbc = fbcs[fbc_idx];
      if(glXGetFBConfigAttrib(dpy, fbc, GLX_VISUAL_ID, (int *)&vid) == Success){
        TRACE("Choosen visual: 0x%x\n", (unsigned)vid);
        if(xcbt_window_gl_create_context(xw, fbc, gl_major, gl_minor, debug)){
          uint32_t eventmask = 
                  XCB_EVENT_MASK_EXPOSURE | // we want to know when we need to redraw
                  XCB_EVENT_MASK_STRUCTURE_NOTIFY | // get varius notification messages like configure, reparent, etc.
                  XCB_EVENT_MASK_PROPERTY_CHANGE | // useful when something will change our property
                  XCB_EVENT_MASK_BUTTON_PRESS | XCB_EVENT_MASK_BUTTON_RELEASE  |  // mouse clicks
                  //XCB_EVENT_MASK_KEY_PRESS | XCB_EVENT_MASK_KEY_RELEASE  |      // keyboard is questionable accordung to XEMBED
                  XCB_EVENT_MASK_ENTER_WINDOW   | XCB_EVENT_MASK_LEAVE_WINDOW |   // mouse entering/leaving
                  XCB_EVENT_MASK_POINTER_MOTION // mouse motion
                  ;
          uint32_t wa[] = { eventmask, 0, 0 };
          xw->wnd = xcb_generate_id(x->conn);
          wa[1] = xw->cmap = xcb_generate_id(x->conn);
          xcb_create_colormap(x->conn, XCB_COLORMAP_ALLOC_NONE, xw->cmap, prt, vid);
          xcb_create_window(x->conn, XCB_COPY_FROM_PARENT, xw->wnd, prt, pos->x, pos->y, pos->w, pos->h, 0,
                            XCB_WINDOW_CLASS_INPUT_OUTPUT, vid, XCB_CW_EVENT_MASK | XCB_CW_COLORMAP, wa);
          // note that at this moment server has no idea we have created the window...
          xw->glwnd = glXCreateWindow(dpy, fbc, xw->wnd, NULL);
          if(xw->glwnd){
            TRACE("GL window 0x%x is created\n", xw->wnd);
            free(fbcs);
            xcbt_window_register(xw);
            return (xcbt_window)xw;
          }
          TRACE("Could not create GL window\n");
        }
      } else {
        TRACE("BUG: best FB config has no Visual\n");
      }
    }
  }
}

void XSys::SetClipboardText(const char* text)
{
    // Fork a process to hold the clipboard text
    // Currently, we use xclip, later on we should do this ourselves

}

void XSys::GetClipboardText(WDL_String& out_text)
{
    _xcbt_window *xw = (_xcbt_window*) pxw;
    _xcbt *x = xw->x;

    // For some reason we don't always receive XCB_SELECTION_CLEAR events
    // so assume we need to request the clipboard content every time.
    // if (x->clipboard_owner != 0)
    // {
    //   _xcbt_window **windows = &x->windows;
    //   while(*windows && ((*windows)->wnd != x->clipboard_owner)){
    //     windows = &(*windows)->x_next;
    //   }
    //   // If we found the clipboard owner, then just return the clipboard data
    //   if (*windows)
    //   {
    //     *length = x->clipboard_length;
    //     return x->clipboard_data;
    //   }
    // }

    // Either we don't own the window with the clipboard, or we don't know who does
    x->clipboard_owner = 0;
    x->clipboard_length = 0;
    free(x->clipboard_data);
    x->clipboard_data = NULL;

    xcb_convert_selection(x->conn, xw->wnd,
        XCBT_ATOM_CLIPBOARD(x), XCBT_ATOM_UTF8_STRING(x), XCBT_ATOM_CLIPBOARD(x), XCB_CURRENT_TIME);
    xcbt_flush(x);

    struct timespec now;
    struct timespec until;
    clock_gettime(CLOCK_MONOTONIC_RAW, &now);
    until = now;
    // Default timeout is 1 second
    until.tv_sec += 1;

    // We have a timeout because getting the clipboard might fail.
    // https://jtanx.github.io/2016/08/19/a-cross-platform-clipboard-library/#linux
    while (x->clipboard_length == 0 && timespec_cmp(&now, &until) < 0)
    {
        xcbt_process((xcbt)x);
        clock_gettime(CLOCK_MONOTONIC_RAW, &now);
    }
    if (x->clipboard_length > 0)
    {
        *length = x->clipboard_length;
        return x->clipboard_data;
    }
    else
    {
        *length = 0;
        return NULL;
    }
}

bool XSys::ProcessEvent(xcb_generic_event* evt)
{
    switch(evt->response_type & ~0x80)
    {
      case XCB_EXPOSE:
      {
        xcb_expose_event_t *ee = (xcb_expose_event_t *)evt;
        auto wnd = mWindows.at(ee->window);
        // TODO collect and use invalidated areas
        IRECT area = IRECT::MakeXYWH((float)ee->x, (float)ee->y, (float)ee->width, (float)ee->height);
        if (!ee->count)
        {
            wnd.listener->Paint(ee->window, area);
        }
      }
      break;
      case XCB_BUTTON_PRESS:
      {
        xcb_button_press_event_t* bp = (xcb_button_press_event_t*) evt;

        if (bp->detail == 1) // check for double-click
        { 
          if (!mLastLeftClickStamp)
          {
            mLastLeftClickStamp = bp->time;
          } 
          else
          {
            if ((bp->time - mLastLeftClickStamp) < 500) // MAYBE: somehow find user settings
            {
              IMouseInfo info = GetMouseInfo(bp->event_x, bp->event_y, bp->state | XCB_BUTTON_MASK_1); // convert button to state mask

              if (OnMouseDblClick(info.x, info.y, info.ms))
              {
                // TODO: SetCapture(hWnd);
              }
              mLastLeftClickStamp = 0;
              xcbt_flush(mX);
              break;
            }
            mLastLeftClickStamp = bp->time;
          }
        }
        else
        {
          mLastLeftClickStamp = 0;
        }
        // TODO: hide tooltips
        // TODO: end parameter editing (if in progress, and return then)
        // TODO: set focus
        
        // TODO: detect double click
        
        // TODO: set capture (or after capture...) (but check other buttons first)
        if ((bp->detail == 1) || (bp->detail == 3)) // left/right
        { 
          uint16_t state = bp->state | (0x80<<bp->detail); // merge state before with pressed button
          IMouseInfo info = GetMouseInfo(bp->event_x, bp->event_y, state); // convert button to state mask
          std::vector<IMouseInfo> list{ info };
          OnMouseDown(list);
        } 
        else if ((bp->detail == 4) || (bp->detail == 5)) // wheel
        { 
          IMouseInfo info = GetMouseInfo(bp->event_x, bp->event_y, bp->state);
          OnMouseWheel(info.x, info.y, info.ms, bp->detail == 4 ? 1. : -1);
        }
        xcb_flush(Conn());
      }
      break;
      case XCB_BUTTON_RELEASE:
      {
        xcb_button_release_event_t* br = (xcb_button_release_event_t*) evt;
        // TODO: release capture (but check other buttons first...)
        if ((br->detail == 1) || (br->detail == 3))
        { // we do not process other buttons, at least not yet
          uint16_t state = br->state & ~(0x80<<br->detail); // merge state before with released button
          IMouseInfo info = GetMouseInfo(br->event_x, br->event_y, state); // convert button to state mask
          std::vector<IMouseInfo> list{ info };
          OnMouseUp(list);
        }
        xcb_flush(Conn());
      }
      break;
      case XCB_MOTION_NOTIFY:
      {
        xcb_motion_notify_event_t* mn = (xcb_motion_notify_event_t*) evt;
        mLastLeftClickStamp = 0;

        if (mn->same_screen && (mn->event == xcbt_window_xwnd(mPlugWnd)))
        {
          // can use event_x/y
          if (!(mn->state & (XCB_BUTTON_MASK_1 | XCB_BUTTON_MASK_3))) // Not left/right drag
          {
            IMouseInfo info = GetMouseInfo(mn->event_x, mn->event_y, mn->state);
            if (OnMouseOver(info.x, info.y, info.ms))
            {
              // TODO: tracking and tooltips
            }
          } 
          else 
          {
            float dX, dY;
            IMouseInfo info = GetMouseInfoDeltas(dX, dY, mn->event_x, mn->event_y, mn->state); //TODO: clean this up

            if (dX || dY)
            {
              info.dX = dX;
              info.dY = dY;
              std::vector<IMouseInfo> list{ info };

              OnMouseDrag(list);
              /* TODO:
              if (MouseCursorIsLocked())
                MoveMouseCursor(pGraphics->mHiddenCursorX, pGraphics->mHiddenCursorY);
                */
            }
          }
        }
        xcb_flush(Conn());
      }
      break;
      case XCB_PROPERTY_NOTIFY:
      {
        xcb_property_notify_event_t* pn = (xcb_property_notify_event_t*) evt;
        if (pn->atom == XCBT_XEMBED_INFO(mX))
        {
            SetVisible(true);

          // TODO: check we really have to, but getting XEMBED_MAPPED and compare with current mapping status
          xcbt_window_map(mPlugWnd);
        }
      }
      break;
      default:
        break;
    }
}
