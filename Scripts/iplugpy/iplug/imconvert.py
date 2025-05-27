import argparse
from PIL import Image
import cairosvg
import sys
import io
import math
from pathlib import Path
from iplug.sizet import SizeT

def load_svg(source: Path, scale: int = 1) -> Image.Image:
  dest = io.BytesIO()
  cairosvg.svg2png(url=f"file://{source}", scale=scale, write_to=dest)
  return Image.open(dest)

def can_sketchy_crop(img: Image.Image, target: SizeT, cutoff: int = 4) -> bool:
  isz = SizeT(*img.size)
  dsz = isz - target
  return dsz.w >= 0 and dsz.w <= cutoff and dsz.h >= 0 and dsz.h <= cutoff

def crop_and_scale(source: Image.Image, target: SizeT) -> 'Image.Image':
  isz = SizeT(*source.size)
  # First "scale up" the target until either width or height is the same as source.
  factor = target.scale_factor_to(isz)
  # We've got the crop size, now we need the area. Currently we just center
  # the smaller size, but later there could be options.
  crop_size = SizeT(round(target.w * factor), round(target.h * factor))
  off_x = (isz.w - crop_size.w) / 2
  off_y = (isz.h - crop_size.h) / 2
  box = (off_x, off_y, isz.w - off_x, isz.h - off_y)
  # Crop and resize!
  return source.crop(box).resize(target)

class ImageConverter:
  def __init__(self, inputs: 'list[Path]', allow_crop: bool = False) -> None:
    self.inputs = inputs
    """List of input paths"""
    self.images: 'list[Image.Image]' = []
    """List of input images, loaded into memory."""
    self.svgs = []
    """
    List of inputs which are SVG images.
    This is actually a tuple of the SVG path, and the rendered default image.
    That way we know the expected size of the SVG.
    """
    self.allow_crop = allow_crop
    """Can we crop larger images if the aspect ratio isn't quite right?"""

    # Load inputs
    for inp in self.inputs:
      if inp.suffix == '.svg':
        img = load_svg(inp)
        self.svgs.append((inp, img))
        self.images.append(img)
      else:
        self.images.append(Image.open(inp))

  def get_sized_output(self, size: 'SizeT') -> 'Image.Image':
    # Try the following options in order:
    # - input with the same size
    # - SVGs with the same aspect ratio, since we can scale
    # - same aspect ratio but larger
    # - Larger images, ONLY if self.allow_crop
    # - images with VERY CLOSE sizes (see `can_sketchy_crop()`)
    # - Smaller images, scaled up

    # Target aspect ratio
    target_ar = size.ratio()
    # List of images with the same aspect ratio
    same_ar_list = []
    # List of images we can sketchy-crop to this size
    sketchy_resize_list = []

    # Check same size, and build up lists of backup candidates
    for img in self.images:
      isz = SizeT(*img.size)
      if isz == size:
        return img
      if isz.ratio() == target_ar:
        same_ar_list.append(img)
      if can_sketchy_crop(img, size):
        sketchy_resize_list.append(img)

    # Now try SVGs with the same aspect ratio since it's safe to scale up
    for path, img in self.svgs:
      isz = SizeT(*img.size)
      if isz.ratio() == target_ar:
        # Determine scaling amount, unfortunately we can only scale by integer
        # amounts so we need to resize back down again afterwards.
        scale = math.ceil(float(isz.w) / size.w)
        scaled_img1 = load_svg(path, scale)
        # Add it to our list of images for the future
        self.images.append(scaled_img1)
        if size == scaled_img1.size:
          return scaled_img1
        # Resize down to meet the requirements
        scaled_img2 = scaled_img1.resize(size)
        self.images.append(scaled_img2)
        return scaled_img2
    
    # Same AR but larger. We know these all have the same aspect ratio,
    # so we can sort by size and pick the lowest one with a larger size.
    if len(same_ar_list) > 0:
      same_ar_list.sort(key=lambda x: SizeT(*x.size))
      for img in same_ar_list:
        if SizeT(*img.size) > size:
          return img.resize(size)
    
    # Try to crop a larger image
    if self.allow_crop:
      for img in self.images:
        if size < img.size:
          continue
        return crop_and_scale(img, size)
      
    # Sketchy resize approach
    if len(sketchy_resize_list) > 0:
      return sketchy_resize_list[0].resize(size)
    
    # Final attempt, look for same AR but SMALLER and scale up.
    # This has the worst quality, but at least it will work.
    larger_i = None
    # We know these are already sorted, so find the first index larger than
    # the requested size. If we fail, then either all images are smaller
    # or there's nothing in the list.
    for i in range(len(same_ar_list)):
      if size > same_ar_list[i].size:
        larger_i = i
        break
    if larger_i is not None or len(same_ar_list) > 0:
      # All images are smaller, so go from the back of the list
      if larger_i is None:
        larger_i = len(same_ar_list)
      source = same_ar_list[larger_i - 1]
      return source.resize()
    
    # That was our final shot. Give up.
    raise ValueError(f'unable to resize an input image to {size}')

  def convert(self, output: Path, format: str, sizes: 'list[SizeT]'):
    output_images = [self.get_sized_output(sz) for sz in sizes]
    out_format = format[1:].upper()

    if len(output_images) > 1:
      if format in ('.ico', '.icns'):
        # Merge into one 
        output_images[0].save(output, out_format, append_images=output_images[1:])
      else:
        # Output multiple image files with suffixes
        pass
    else:
      # Just one image
      output_images[0].save(output, out_format)

def main(argv = None):
  if argv is None:
    argv = ['imconvert'] + sys.argv[1:]

  parser = argparse.ArgumentParser(
    prog=argv[0],
    description='iPlug image conversion utility')
  parser.add_argument(
    '-i', '--input', action='append', default=[], type=Path,
    help='Input file, may be given multiple times for multiple inputs')
  parser.add_argument(
    '-s', '--size', type=str, action='append', default=[],
    help='''
    Output size(s) in the format "<width>x<height>". Height may be omitted if
    it's the same as width. Multiple sizes can be given, in which case the
    output will either produce multiple files, with different suffixes, or
    combine the sizes into one output (e.g. for .ico or .icns files).
    ''')
  parser.add_argument(
    '--crop', action='store_true',
    help='Crop the input(s) to fit the desired output size(s).')
  parser.add_argument(
    'output', type=Path,
    help='Output file. The extension determines the type.')
  args = parser.parse_args(argv[1:])

  sizes = [SizeT.parse(s) for s in args.size]
  dest = Path(args.output)
  conv = ImageConverter(args.input, allow_crop=args.crop)
  conv.convert(dest, dest.suffix, sizes)

if __name__ == '__main__':
  main()

