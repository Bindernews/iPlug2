#include "IControl.h"
#include "IGraphics.h"
#include "IGraphicsStructs.h"
#include "IPlugUtilities.h"
#include "heapbuf.h"
#include <cmath>

using namespace iplug;
using namespace iplug::igraphics;

class ColorPickerControl : public IControl
{
public:
  enum EMode { kModeCircle, kModeSquare };

  ColorPickerControl(const IRECT& bounds);

  virtual void Draw(IGraphics& g) override;
  virtual void OnMouseDown(float x, float y, const IMouseMod& mod) override;
  virtual void OnMouseUp(float x, float y, const IMouseMod& mod) override;
  virtual void OnMouseOver(float x, float y, const IMouseMod& mod) override;


protected:
  /** Snap the given hue and saturation values to the grid.
   * Interanlly sets mHue and mSat. */
  virtual void SnapColor(float hue, float sat);

private:
  void CreateColorBitmaps(int w, int h);
  float OffsetHue(float h, bool negate=false);
  void DrawSnapCircle(IGraphics &g);
  void DrawSnapGrid(IGraphics& g);

  void UpdateMouse(float x, float y, const IMouseMod& mod);
  void RescaleUI(float scale);

  // Style fields
  int mHueLines = 16;
  int mSatLines = 6;
  float mGridThickness;
  float mSelCircleRadius;
  float mSelCircleThickness;
  float mCornerRadius = 5.f;
  IRECT mColorBox;
  IRECT mLightBox;
  IRECT mCurrentBox;
  IColor mLineColor;
  IText mColorText;
  
  // State fields
  bool mMouseDown;
  bool mSnap;
  EMode mMode;
  float mHue;
  float mSat;
  float mLum;
  IBitmap mColorCircle;
  IBitmap mColorSquare;

  // Helper fields
  WDL_String mStr; // Temp string
};

const float PI2 = 3.14159f * 2.f;

#define STR_BUF (1024)

ColorPickerControl::ColorPickerControl(const IRECT& bounds)
: IControl(bounds, nullptr)
{
  mColorText.mAlign = EAlign::Center;
  mColorText.mVAlign = EVAlign::Middle;
}

void ColorPickerControl::Draw(IGraphics& g)
{
  float selCX, selCY;

  if (mMode == kModeCircle)
  {
    g.DrawBitmap(mColorCircle, mColorBox);
    if (mSnap)
    {
      DrawSnapCircle(g);
    }
    // Draw the circle outline
    g.DrawCircle(COLOR_BLACK, mColorBox.MW(), mColorBox.MH(), mColorBox.W() / 2.f);
    // Position selection circle
    PolarToCart(mHue * 2.f, mSat * (mColorBox.W() / 2.f), selCX, selCY);
  }
  else
  {
    g.DrawBitmap(mColorSquare, mColorBox);
    if (mSnap)
    {
      DrawSnapGrid(g);
    }
    // Position selection circle
    selCX = Lerp(mColorBox.L, mColorBox.R, OffsetHue(mHue, true));
    selCY = Lerp(mColorBox.T, mColorBox.B, 1 - mSat);
  }

  // Draw the selection circle
  g.DrawCircle(COLOR_WHITE, selCX, selCY, mSelCircleRadius, nullptr, mSelCircleThickness);

  // Draw the lightness scale
  {
    IColor color = IColor::FromHSLA(mHue, mSat, 0.5f);
    IRECT b = mLightBox.GetFromTop(mLightBox.H() / 2.f);
    // We split this into two gradients b/c NanoVG only supports 2 stops on gradients.
    // Also it's how my original code works due to similar limits.
    g.PathRect(b);
    g.PathFill(IPattern::CreateLinearGradient(b, EDirection::Vertical, 
        { IColorStop(COLOR_WHITE, 0.f), IColorStop(color, 1.f) }));
    b = mLightBox.GetFromBottom(mLightBox.H() / 2.f);
    g.PathRect(b);
    g.PathFill(IPattern::CreateLinearGradient(b, EDirection::Vertical,
        { IColorStop(color, 0.f), IColorStop(COLOR_BLACK, 1.f) }));

    // Draw currently selected lightness
    float cx = mLightBox.MW();
    float cy = Lerp(mLightBox.T, mLightBox.B, 1.f - mLum);
    g.DrawCircle(COLOR_WHITE, cx, cy, mSelCircleRadius, nullptr, mSelCircleThickness);
  }

  // Draw current color
  {
    IColor color = IColor::FromHSLA(mHue, mSat, mLum);
    g.FillRoundRect(color, mCurrentBox, mCornerRadius);
    g.DrawRoundRect(COLOR_BLACK, mCurrentBox, mCornerRadius);

    // Draw color value as text
    IColor textColor;
    if (mSat == 0.f)
      textColor = COLOR_BLACK;
    else
      textColor = IColor::FromHSLA(mHue, mSat, Wrap(0.f, 1.f, mLum + 0.5f));
    mStr.SetFormatted(STR_BUF, "Color\n#%06X", color.ToColorCode());
    g.DrawText(mColorText, mStr.Get(), mCurrentBox.MW(), mCurrentBox.MH());
  }

  {

  }
  
}

void ColorPickerControl::OnMouseDown(float x, float y, const IMouseMod& mod)
{
  mMouseDown = true;
  UpdateMouse(x, y, mod);
}

void ColorPickerControl::OnMouseUp(float x, float y, const IMouseMod& mod)
{
  mMouseDown = false;
  UpdateMouse(x, y, mod);
}

void ColorPickerControl::OnMouseOver(float x, float y, const IMouseMod& mod)
{
  UpdateMouse(x, y, mod);
}

void ColorPickerControl::SnapColor(float hue, float sat)
{
  // Snap hue and saturation
  float hStep = (float)mHueLines;
  float sStep = (float)mSatLines;
  
  // Snapping hue is fairly easy.
  float h = std::round(hue * hStep) / hStep;
  if (h == 1.f)
    h = 0.f;

  // To snap saturation, we have to perform the offset ourselves
  // We do this by basically doing floor(sat - half_step), rounding correctly, then
  // adding back the half_step we took away earlier. This gives us vales between
  // the grid lines instead of on them.
  float sOff = 1.f / (sStep * 2.f);
  float s = sat - sOff;
  s = Clip(0.f, 1.f - (sOff * 2.f), s);
  s = std::round(s * sStep) / sStep;
  s = s + sOff;
  mSat = s;
}

void ColorPickerControl::CreateColorBitmaps(int w, int h)
{
  struct Color8
  {
    uint8_t r, g, b, a;

    static Color8 FromIColor(const IColor& c)
    {
      return Color8 { (uint8_t)c.R, (uint8_t)c.G, (uint8_t)c.B, (uint8_t)c.A };
    }
  };

  const Color8 TRANSPARENT = Color8 { 0, 0, 0, 0 };

  // Create the color circle
  WDL_TypedBuf<Color8> imageCircle;
  Color8* imageDataC = imageCircle.Resize(w * h);
  int cx = w / 2;
  int cy = h / 2;
  for (int y = 0; y < h; y++)
  {
    for (int x = 0; x < w; x++)
    {
      int idx = (y * w) + x;
      float rx = x - cx;
      float ry = y - cy;
      float ang = std::atan2(ry, rx);
      float dist = std::sqrtf((rx * rx) + (ry * ry));
      if (dist > (float)cx)
      {
        imageDataC[idx] = TRANSPARENT;
      }
      else
      {
        float h = (ang / PI2), s = (dist / (float)cx), l = 0.5f;
        IColor co = IColor::FromHSLA(h, s, l, 1.f);
        imageDataC[idx] = Color8::FromIColor(co);
      }
    }
  }

  // Create the color square
  WDL_TypedBuf<Color8> imageSquare;
  Color8* imageDataS = imageSquare.Resize(w * h);
  for (int y = 0; y < h; y++)
  {
    for (int x = 0; x < w; x++)
    {
      int idx = (y * w) + x;
      float h = (float)x / float(w), s = (float)y / (float)h;
      IColor co = IColor::FromHSLA(OffsetHue(h), s, 0.5f, 1.f);
      imageDataS[idx] = Color8::FromIColor(co);
    }
  }

  // TODO create bitmaps from raw RGBA data
  
}

float ColorPickerControl::OffsetHue(float h, bool negate)
{
  float off = 1 / (float)(mHueLines * 2);
  if (negate)
  {
    h += off;
    if (h > 1.f)
      h -= 1.f;
  }
  else
  {
    h -= off;
    if (h < 0.f)
      h += 1.f;
  }
  return h;
}

void ColorPickerControl::DrawSnapCircle(IGraphics& g)
{
  float hueLF = (float)mHueLines, satLF = (float)mSatLines;
  float ringF = 1.f / satLF;
  float cx = mColorBox.MW(), cy = mColorBox.MH();
  float r = mColorBox.W() / 2.f;
  float r0 = (r * ringF) + 0.5f;
  float r1 = r - 0.5f;

  // Draw hue lines
  for (int i = 1; i <= mHueLines; i++)
  {
    float ang = (((float)i + 0.5f) / hueLF) * PI2;
    float c = std::cosf(ang), s = std::sinf(ang);
    g.DrawLine(mLineColor, cx + (c * r0), cy + (s * r0), cx + (c * r1), cy + (s * r1));
  }

  // Draw saturation rings
  for (int i = 1; i <= mSatLines; i++)
  {
    float cr = (float)i * ringF * r;
    g.DrawCircle(mLineColor, cx, cy, cr);
  }
}

void ColorPickerControl::DrawSnapGrid(IGraphics& g)
{
  IRECT b = mColorBox;

  // Hue lines
  for (int i = 0; i < mHueLines; i++)
  {
    float x = Lerp(b.L, b.R, (float)i / (float)mHueLines);
    g.DrawLine(mLineColor, x, b.T, x, b.B);
  }

  // Saturation lines
  for (int i = 0; i < mSatLines; i++)
  {
    float y = Lerp(b.T, b.B, (float)i / (float)mSatLines);
    g.DrawLine(mLineColor, b.L, y, b.R, y);
  }
}

void ColorPickerControl::UpdateMouse(float x, float y, const IMouseMod& mod)
{

  // If the user is clicking or dragging
  if (mod.L || mMouseDown)
  {
    // Handle the user clicking on the color picker
    if (mColorBox.Contains(x, y))
    {
      float nx, ny;
      if (mMode == kModeCircle)
      {
        float ang, r;
        CartToPolar(x, y, ang, r);
        float maxRadius = mColorBox.W() / 2.f;
        // If the radius is within the color circle it's valid
        if (r <= maxRadius)
        {
          mHue = ang / 2.f;
          mSat = r / maxRadius;
        }
      }
      else // if mMode == kModeSquare
      {
        float hue = Unlerp(mColorBox.L, mColorBox.R, x);
        float sat = Unlerp(mColorBox.T, mColorBox.B, y);
        mHue = OffsetHue(hue, false);
        mSat = 1.f - sat;
      }
      // Handle snapping
      if (mSnap)
      {
        SnapColor(mHue, mSat);
      }
    }
    
    // Handle lightbox click/dag

  }
  
}

void ColorPickerControl::RescaleUI(float scale)
{
  mSelCircleRadius = 6.f * scale;
  mSelCircleThickness = 2.f;
}

