import image;
import vtoc;

class MydosVtoc : Vtoc
{
	this(Image img)
	{
		image_ = img;
	}

	override bool opIndexImpl(uint sector)
	{
		return !!(vtocByte(sector) & (1 << (sector % 8)));
	}

	override bool opIndexAssignImpl(bool value, uint sector)
	{
		vtocByte(sector) &= ~(1 << (sector % 8));
		if (value)
			vtocByte(sector) |= 1 << (sector % 8);
		modified_ = true;
		return value;
	}

	override void flush()
	{
		if (vtocSectorNo_ && modified_)
			image_.writeSector(vtocSectorNo_, vtocSector_);
		modified_ = false;
	}

	@property override Image image()
	{
		return image_;
	}

private:
	ref ubyte vtocByte(uint sector)
	{
		uint vb = vtocByte(10 + sector / 8);
		uint vsn = 360 - vb / image_.bytesPerSector;
		if (vsn != vtocSectorNo_)
		{
			flush();
			image_.readSector(vsn, vtocSector_);
			vtocSectorNo_ = vsn;
		}
		return vtocSector_[vb % image_.bytesPerSector];
	}

	Image image_;
	ubyte[] vtocSector_;
	uint vtocSectorNo_ = 0;
	bool modified_;
}
