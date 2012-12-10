void rt_init(void);
void rt_term(void);

void XeDisk_Init(void)
{
	rt_init();
}

void XeDisk_Quit(void)
{
	rt_term();
}
