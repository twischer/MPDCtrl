package Display::GLCD;
use strict;
use warnings;
use utf8;
use Time::HiRes();
use Thread();
use Thread::Queue();
use Inline C => <<'END_C';
#include <stdio.h>
#include <stdlib.h>
#include <sys/io.h>
#include <unistd.h>
#include <string.h>
#include <stdbool.h>

#include "Display/font1.h"
#include "Display/font2.h"
#include "Display/font3.h"

#define LPT_PORT_DATA		0x378
#define LPT_PORT_CONTROL	0x37A
#define LPT_PIN_STROBE		0x01	// invertiert
#define LPT_PIN_FEED		0x02	// invertiert
#define LPT_PIN_RESET		0x04
#define LPT_PIN_SELECTIN	0x08

#define LCD_ENABLE			LPT_PIN_STROBE
#define LCD_CS1				(LPT_PIN_FEED | LPT_PIN_RESET)
#define LCD_CS2				0x00
#define LCD_RS				LPT_PIN_SELECTIN

#define DELAY				300

// Befehle vom Display
#define DISPLAY_ON         0x3F
#define DISPLAY_OFF        0x3E
#define DISPLAY_STARTLINE  0xC0
#define DISPLAY_PAGE_SET   0xB8
#define DISPLAY_COLUMN_SET 0x40

#define SCROLL_TEXT_SHIFTER		1
#define SCROLL_TEXT_SPACES		5
#define SCROLL_TEXT_DATA_COUNT	2
#define SCROLL_TEXT_DATA_MAXLEN	1024
struct grScrollingTextData
{
	int nYPos;
	int nLines;
	int nLength;
	unsigned char aacData[SCROLL_TEXT_DATA_COUNT][SCROLL_TEXT_DATA_MAXLEN];
	int nCurPos;
};

unsigned char CurrentColumn;
struct grScrollingTextData m_agrScrollingTextData[4];
int m_nZeile = 0;
int m_nSpalte = 0;

const int m_anFontCharLength[] = { 8, 5, 16 };
const int m_anFontCharLines[] = { 1, 1, 2 };


//---------------------------------------------------------------------------
// WritePort()
//---------------------------------------------------------------------------
void GLCD_WritePort(int Address, unsigned char Data)
{
	outb(Data, Address);
}

//---------------------------------------------------------------------------
// Delay()
//---------------------------------------------------------------------------
void GLCD_Delay()
{
	int i;
	for (i=0; i<=DELAY; i++)
	{
		__asm__ __volatile__("nop");
	}
}

//---------------------------------------------------------------------------
// SendCommand()
//---------------------------------------------------------------------------
void GLCD_SendCommand(unsigned char value, unsigned char CS)
{
	GLCD_WritePort(LPT_PORT_CONTROL, LCD_ENABLE | CS | LCD_RS);
	GLCD_WritePort(LPT_PORT_DATA, value);
	GLCD_WritePort(LPT_PORT_CONTROL, CS | LCD_RS);
	GLCD_Delay();
	GLCD_WritePort(LPT_PORT_CONTROL, LCD_ENABLE | CS | LCD_RS);
	GLCD_Delay();
}


//---------------------------------------------------------------------------
// SendData()
//---------------------------------------------------------------------------
bool GLCD_SendData(unsigned char values[], unsigned int amount)
{
	if (values == NULL)
		return false;
	
	unsigned int counter;
	for (counter=0; counter < amount; counter++)
	{
		unsigned char cs;
		cs = m_nSpalte>63?LCD_CS2:LCD_CS1;
		
		GLCD_WritePort(LPT_PORT_CONTROL, LCD_ENABLE | cs);
		GLCD_WritePort(LPT_PORT_DATA, values[counter]);
		GLCD_WritePort(LPT_PORT_CONTROL, cs);
		GLCD_Delay();
		GLCD_WritePort(LPT_PORT_CONTROL, LCD_ENABLE | cs);
		GLCD_Delay();
		
		m_nSpalte++;
		if (m_nSpalte > 127)
		{
			return false;
		}
	}
	
	return true;
}

//---------------------------------------------------------------------------
// On()
//---------------------------------------------------------------------------
void GLCD_On()
{
	GLCD_SendCommand(DISPLAY_ON, LCD_CS1);
	GLCD_SendCommand(DISPLAY_ON, LCD_CS2);
}

//---------------------------------------------------------------------------
// Off()
//---------------------------------------------------------------------------
void GLCD_Off()
{
	GLCD_SendCommand(DISPLAY_OFF, LCD_CS1);
	GLCD_SendCommand(DISPLAY_OFF, LCD_CS2);
}

//---------------------------------------------------------------------------
// SetColumn()
//---------------------------------------------------------------------------
void GLCD_SetColumn(unsigned char y)
{
	m_nSpalte = y;
	if (y < 64)
	{
		GLCD_SendCommand(DISPLAY_COLUMN_SET | (y&63), LCD_CS1);
		GLCD_SendCommand(DISPLAY_COLUMN_SET | 0, LCD_CS2);
	} 
	else
	{
		GLCD_SendCommand(DISPLAY_COLUMN_SET | 63, LCD_CS1);
		GLCD_SendCommand(DISPLAY_COLUMN_SET | ((y-64)&63), LCD_CS2);
	}
}

//---------------------------------------------------------------------------
// SetPage()
//---------------------------------------------------------------------------
void GLCD_SetPage(unsigned char x)
{
	GLCD_SendCommand(DISPLAY_PAGE_SET | x, LCD_CS1);
	GLCD_SendCommand(DISPLAY_PAGE_SET | x, LCD_CS2);

	m_nZeile = x;
}

//---------------------------------------------------------------------------
// SetXY()
//---------------------------------------------------------------------------
void GLCD_SetXY(int x, int y)
{
	GLCD_SetColumn(x);
	GLCD_SetPage(y);
}

//---------------------------------------------------------------------------
// Clear()
//---------------------------------------------------------------------------
void GLCD_Clear(int nStart, int nEnde)
{
	if (nStart < 0)
	{
		nStart = 0;
	}
	if (nEnde > 7)
	{
		nEnde = 7;
	}
	
	int i;
	for (i=nStart; i<=nEnde; i++)
	{
		GLCD_SetPage(i);
		GLCD_SetColumn(0);
		int j;
		for (j=0; j<128; j++)
		{
			unsigned char chZero = 0x00;
			GLCD_SendData( &chZero, 1 );
		}
	}
}

//---------------------------------------------------------------------------
// GLCD_GetFontPointer()
//---------------------------------------------------------------------------
unsigned char* GLCD_GetFontPointer(int nFont, int nChar)
{
	switch (nFont)
	{
		case 0:
			return (unsigned char*)&Character8x8[ nChar * m_anFontCharLength[nFont] ];
			
		case 1:
			return (unsigned char*)&font5x7[ (nChar - 32) * m_anFontCharLength[nFont] ];
			
		case 2:
			return (unsigned char*)&Font16x16[ (nChar - 32) * m_anFontCharLength[nFont] * m_anFontCharLines[nFont] ];
			
		default:
			fprintf(stderr,"GLCD_GetFontPointer: Zeichensatz existiert nicht! (%i, %c)\n", nFont, nChar);
			return NULL;
	}
}

//---------------------------------------------------------------------------
// GLCD_Print()
//---------------------------------------------------------------------------
void GLCD_Print(int nFont, char *szText)
{
	while (*szText != 0)
	{
		switch (nFont)
		{
			case 0:
				GLCD_SendData( GLCD_GetFontPointer(nFont, *szText), m_anFontCharLength[nFont] );
				break;

			case 1:
				if ( GLCD_SendData( GLCD_GetFontPointer(nFont, *szText), m_anFontCharLength[nFont] ) )
				{
					unsigned char chZero = 0x00;
//					GLCD_SendData( &chZero, 1 );
				}
				break;

			case 2:
				GLCD_SendData( GLCD_GetFontPointer(nFont, *szText) + m_anFontCharLength[nFont], m_anFontCharLength[nFont] );
				GLCD_SetPage(m_nZeile+1);
				GLCD_SetColumn(m_nSpalte-16);

				GLCD_SendData( GLCD_GetFontPointer(nFont, *szText), m_anFontCharLength[nFont] );
				GLCD_SetPage(m_nZeile-1);
				break;
			default:
				fprintf(stderr,"GLCD_Print: Zeichensatz existiert nicht (%i, %c)\n", nFont, *szText);
		}
		
		if (m_nSpalte > 127)
			return;
		
		szText++;
	}
}

//---------------------------------------------------------------------------
// GLCD_DeleteScrollingText()
//---------------------------------------------------------------------------
void GLCD_DeleteScrollingText(int nID)
{
	if (  (nID < 0) || ( nID > (sizeof(m_agrScrollingTextData) / sizeof(struct grScrollingTextData) - 1) )  )
		return;
	
	m_agrScrollingTextData[nID].nYPos = 0;
	m_agrScrollingTextData[nID].nLines = 0;
	m_agrScrollingTextData[nID].nLength = 0;
	m_agrScrollingTextData[nID].nCurPos = 0;
}

//---------------------------------------------------------------------------
// GLCD_SetScrollingText()
//---------------------------------------------------------------------------
void GLCD_SetScrollingText(int nID, int nY, int nFont, char *szText)
{
	if (  (nID < 0) || ( nID > (sizeof(m_agrScrollingTextData) / sizeof(struct grScrollingTextData) - 1) )  )
		return;
	
	GLCD_DeleteScrollingText(nID);
	
	int nLength = m_anFontCharLength[nFont] * strlen(szText);
	if (nLength <= 128)
	{
		GLCD_Clear(nY, nY + m_anFontCharLines[nFont] - 1);
		GLCD_SetXY(0, nY);
		
		GLCD_Print(nFont, szText);
	}
	else
	{
		m_agrScrollingTextData[nID].nYPos = nY;
		m_agrScrollingTextData[nID].nLines = m_anFontCharLines[nFont];
		m_agrScrollingTextData[nID].nLength = nLength + m_anFontCharLength[nFont] * SCROLL_TEXT_SPACES;
		m_agrScrollingTextData[nID].nCurPos = 0;
		
		int nTextDataPos = 0;
		while (*szText != 0)
		{
			unsigned char *pacCharData = GLCD_GetFontPointer(nFont, *szText);
			int i;
			for (i=0; i<m_agrScrollingTextData[nID].nLines; i++)
			{
				int nOffset = m_anFontCharLength[nFont] * (m_agrScrollingTextData[nID].nLines - i - 1);
				unsigned char *pacCharData2 = pacCharData + nOffset;
				unsigned char *pacTextData = m_agrScrollingTextData[nID].aacData[i] + nTextDataPos;
				memcpy( pacTextData, pacCharData2, m_anFontCharLength[nFont] );
			}
			
			szText++;
			nTextDataPos += m_anFontCharLength[nFont];
		}
		
		while (nTextDataPos < m_agrScrollingTextData[nID].nLength)
		{
			int i;
			for (i=0; i<m_agrScrollingTextData[nID].nLines; i++)
			{
				unsigned char *pacTextData = m_agrScrollingTextData[nID].aacData[i] + nTextDataPos;
				*pacTextData = 0x00;
			}
			nTextDataPos++;
		}
	}
}

//---------------------------------------------------------------------------
// GLCD_UpdateScrollingText()
//---------------------------------------------------------------------------
void GLCD_UpdateScrollingText()
{
	int i;
	for (i=0; i<sizeof(m_agrScrollingTextData)/sizeof(struct grScrollingTextData); i++)
	{
		if (m_agrScrollingTextData[i].nLength > 0)
		{
			int j;
			for (j=0; j<m_agrScrollingTextData[i].nLines; j++)
			{
				GLCD_SetXY(0, m_agrScrollingTextData[i].nYPos + j);
				
				unsigned char *pacData = m_agrScrollingTextData[i].aacData[j] + m_agrScrollingTextData[i].nCurPos;
				int nLength = m_agrScrollingTextData[i].nLength - m_agrScrollingTextData[i].nCurPos;
				bool bEndNotReached = GLCD_SendData( pacData, nLength );
				
				if (bEndNotReached)
					GLCD_SendData( m_agrScrollingTextData[i].aacData[j], m_agrScrollingTextData[i].nLength );
			}
				
			m_agrScrollingTextData[i].nCurPos += m_agrScrollingTextData[i].nLines * SCROLL_TEXT_SHIFTER;
			if (m_agrScrollingTextData[i].nCurPos > m_agrScrollingTextData[i].nLength)
				m_agrScrollingTextData[i].nCurPos = 0;
		}
	}
}

//---------------------------------------------------------------------------
// GLCD_Init()
//---------------------------------------------------------------------------
void GLCD_Init()
{
	int i;
	for (i=0; i<sizeof(m_agrScrollingTextData)/sizeof(struct grScrollingTextData); i++)
		GLCD_DeleteScrollingText(i);
	
	if (ioperm(LPT_PORT_DATA, 3, 1) != 0)
	{
		fprintf(stderr,"kein Zugriff. Muss als root laufen !\n");
		exit(1);
	}
	
	GLCD_On();

	GLCD_Clear(0, 7);
}

//---------------------------------------------------------------------------
// GLCD_DeInit()
//---------------------------------------------------------------------------
void GLCD_DeInit()
{
	if (ioperm(LPT_PORT_DATA, 3, 0) != 0)
	{
		fprintf(stderr,"kein Zugriff. Muss als root laufen !\n");
		exit(1);
	}
}

END_C
require Logger;

########################################################################################################################
sub new
########################################################################################################################
{
	my ($proto) = @_;
	
	my $self  = {};
		
	my $class = ref($proto) || $proto;
	bless ($self, $class);
	
	Logger->GetInstance()->Write( $self, 2, "Starting thread ..." );
	$self->{'pobjQueue'} = new Thread::Queue();
	$self->{'pobjThread'} = new Thread( \&WorkerThread, $self, $self->{'pobjQueue'} );
	
	return $self;
}

########################################################################################################################
sub Destroy
########################################################################################################################
{
	my ($self) = @_;
	
	$self->{'pobjQueue'}->enqueue( "TERM" );
	$self->{'pobjThread'}->join();
}

########################################################################################################################
sub WorkerThread
########################################################################################################################
{
	my ($self, $pobjQueue) = @_;
	
	my %mpaszFunctions = (
		'SetXY'					=> [ 2, \&GLCD_SetXY ],
		'Print'					=> [ 2, \&GLCD_Print ],
		'Clear'					=> [ 2, \&GLCD_Clear ],
		'On'					=> [ 0, \&GLCD_On ],
		'Off'					=> [ 0, \&GLCD_Off ],
		'SetScrollingText'		=> [ 4, \&GLCD_SetScrollingText ],
		'DeleteScrollingText'	=> [ 1, \&GLCD_DeleteScrollingText ],
		);
	
	GLCD_Init();
	
	Logger->GetInstance()->Write( $self, 2, "Thread started" );
	
	my $fWorking = 1;
	while ($fWorking)
	{
		GLCD_UpdateScrollingText();
		
		while ( my $szCommand = $pobjQueue->dequeue_nb() )
		{
			if ($szCommand eq "TERM")
			{
				$fWorking = 0;
				last;
			}
			elsif ( defined $mpaszFunctions{$szCommand} )
			{
				my $nArgCount = $mpaszFunctions{$szCommand}->[0];
				my $pFunction = $mpaszFunctions{$szCommand}->[1];
					
					if ($nArgCount == 0)
					{
						&$pFunction();
					}
					elsif ($nArgCount == 1)
					{
						&$pFunction( $pobjQueue->dequeue() );
					}
					elsif ($nArgCount == 2)
					{
						&$pFunction( $pobjQueue->dequeue(), $pobjQueue->dequeue() );
					}
					elsif ($nArgCount == 3)
					{
						&$pFunction( $pobjQueue->dequeue(), $pobjQueue->dequeue(), $pobjQueue->dequeue() );
					}
					elsif ($nArgCount == 4)
				{
					&$pFunction( $pobjQueue->dequeue(), $pobjQueue->dequeue(), $pobjQueue->dequeue(), $pobjQueue->dequeue() );
				}
			}
			else
			{
				Logger->GetInstance()->Write( $self, 1, "Unkown command $szCommand" );
			}
		}
		
		Time::HiRes::sleep( 1/20 );
	}
	
	GLCD_DeInit();
}

########################################################################################################################
sub SetXY
########################################################################################################################
{
	my ($self, $nX, $nY) = @_;
	
	$self->{'pobjQueue'}->enqueue( "SetXY", $nX, $nY );
}

########################################################################################################################
sub Print
########################################################################################################################
{
	my ($self, $szText, $nFont) = @_;
	
	unless (defined $nFont)
	{
		$nFont = 0;
	}
	utf8::decode( $szText );
	
	$self->{'pobjQueue'}->enqueue( "Print", $nFont, $szText );
}

########################################################################################################################
sub Clear
########################################################################################################################
{
	my ($self, $nYStart, $nYEnd) = @_;
	
	if ( (not defined $nYStart) or (not defined $nYEnd) )
	{
		$nYStart = 0;
		$nYEnd = 0;
	}
	
	$self->{'pobjQueue'}->enqueue( "Clear", $nYStart, $nYEnd );
}

########################################################################################################################
sub On
########################################################################################################################
{
	my ($self) = @_;
	
	$self->{'pobjQueue'}->enqueue( "On" );
}

########################################################################################################################
sub Off
########################################################################################################################
{
	my ($self) = @_;
	
	$self->{'pobjQueue'}->enqueue( "Off" );
}

########################################################################################################################
sub SetScrollingText
########################################################################################################################
{
	my ($self, $nID, $nYPos, $szText, $nFont) = @_;
	
	unless (defined $nFont)
	{
		$nFont = 0;
	}
	utf8::decode( $szText );
	
	$self->{'pobjQueue'}->enqueue( "SetScrollingText", $nID, $nYPos, $nFont, $szText );
}

########################################################################################################################
sub DeleteScrollingText
########################################################################################################################
{
	my ($self, $nID) = @_;
	
	$self->{'pobjQueue'}->enqueue( "DeleteScrollingText", $nID );
}

1;
