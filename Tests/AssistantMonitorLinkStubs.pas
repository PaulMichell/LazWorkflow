Unit AssistantMonitorLinkStubs;

{ Link symbols for widgetset-free monitor console tests (c) 2026 Michell Computing.

  AssistantMonitorCodec uses GrokOAuth, and that unit uses Forms. The LCL
  widgetset units then reference WSRegister symbols that Interfaces would
  define. These tests must not use Interfaces and must not open a widgetset.
  The functions below only satisfy the linker. They do not create a widgetset. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
  {$SMARTLINK OFF}
{$ENDIF}

Interface

Implementation

Function WSRegisterCustomImageListResolution: Boolean; Public Name 'WSRegisterCustomImageListResolution';
Begin Result := False; End;
Function WSRegisterDragImageListResolution: Boolean; Public Name 'WSRegisterDragImageListResolution';
Begin Result := False; End;
Function WSRegisterLazAccessibleObject: Boolean; Public Name 'WSRegisterLazAccessibleObject';
Begin Result := False; End;
Function WSRegisterControl: Boolean; Public Name 'WSRegisterControl';
Begin Result := False; End;
Function WSRegisterWinControl: Boolean; Public Name 'WSRegisterWinControl';
Begin Result := False; End;
Function WSRegisterGraphicControl: Boolean; Public Name 'WSRegisterGraphicControl';
Begin Result := False; End;
Function WSRegisterCustomControl: Boolean; Public Name 'WSRegisterCustomControl';
Begin Result := False; End;
Function WSRegisterStatusBar: Boolean; Public Name 'WSRegisterStatusBar';
Begin Result := False; End;
Function WSRegisterTabSheet: Boolean; Public Name 'WSRegisterTabSheet';
Begin Result := False; End;
Function WSRegisterPageControl: Boolean; Public Name 'WSRegisterPageControl';
Begin Result := False; End;
Function WSRegisterCustomListView: Boolean; Public Name 'WSRegisterCustomListView';
Begin Result := False; End;
Function WSRegisterCustomProgressBar: Boolean; Public Name 'WSRegisterCustomProgressBar';
Begin Result := False; End;
Function WSRegisterCustomUpDown: Boolean; Public Name 'WSRegisterCustomUpDown';
Begin Result := False; End;
Function WSRegisterCustomToolButton: Boolean; Public Name 'WSRegisterCustomToolButton';
Begin Result := False; End;
Function WSRegisterToolBar: Boolean; Public Name 'WSRegisterToolBar';
Begin Result := False; End;
Function WSRegisterCustomTrackBar: Boolean; Public Name 'WSRegisterCustomTrackBar';
Begin Result := False; End;
Function WSRegisterCustomTreeView: Boolean; Public Name 'WSRegisterCustomTreeView';
Begin Result := False; End;
Function WSRegisterCustomCalendar: Boolean; Public Name 'WSRegisterCustomCalendar';
Begin Result := False; End;
Function WSRegisterCommonDialog: Boolean; Public Name 'WSRegisterCommonDialog';
Begin Result := False; End;
Function WSRegisterFileDialog: Boolean; Public Name 'WSRegisterFileDialog';
Begin Result := False; End;
Function WSRegisterOpenDialog: Boolean; Public Name 'WSRegisterOpenDialog';
Begin Result := False; End;
Function WSRegisterSaveDialog: Boolean; Public Name 'WSRegisterSaveDialog';
Begin Result := False; End;
Function WSRegisterSelectDirectoryDialog: Boolean; Public Name 'WSRegisterSelectDirectoryDialog';
Begin Result := False; End;
Function WSRegisterColorDialog: Boolean; Public Name 'WSRegisterColorDialog';
Begin Result := False; End;
Function WSRegisterColorButton: Boolean; Public Name 'WSRegisterColorButton';
Begin Result := False; End;
Function WSRegisterFontDialog: Boolean; Public Name 'WSRegisterFontDialog';
Begin Result := False; End;
Function WSRegisterTaskDialog: Boolean; Public Name 'WSRegisterTaskDialog';
Begin Result := False; End;
Function WSRegisterCustomScrollBar: Boolean; Public Name 'WSRegisterCustomScrollBar';
Begin Result := False; End;
Function WSRegisterCustomGroupBox: Boolean; Public Name 'WSRegisterCustomGroupBox';
Begin Result := False; End;
Function WSRegisterCustomComboBox: Boolean; Public Name 'WSRegisterCustomComboBox';
Begin Result := False; End;
Function WSRegisterCustomListBox: Boolean; Public Name 'WSRegisterCustomListBox';
Begin Result := False; End;
Function WSRegisterCustomEdit: Boolean; Public Name 'WSRegisterCustomEdit';
Begin Result := False; End;
Function WSRegisterCustomMemo: Boolean; Public Name 'WSRegisterCustomMemo';
Begin Result := False; End;
Function WSRegisterButtonControl: Boolean; Public Name 'WSRegisterButtonControl';
Begin Result := False; End;
Function WSRegisterCustomButton: Boolean; Public Name 'WSRegisterCustomButton';
Begin Result := False; End;
Function WSRegisterCustomCheckBox: Boolean; Public Name 'WSRegisterCustomCheckBox';
Begin Result := False; End;
Function WSRegisterToggleBox: Boolean; Public Name 'WSRegisterToggleBox';
Begin Result := False; End;
Function WSRegisterRadioButton: Boolean; Public Name 'WSRegisterRadioButton';
Begin Result := False; End;
Function WSRegisterCustomStaticText: Boolean; Public Name 'WSRegisterCustomStaticText';
Begin Result := False; End;
Function WSRegisterCustomLabel: Boolean; Public Name 'WSRegisterCustomLabel';
Begin Result := False; End;
Function WSRegisterCustomPage: Boolean; Public Name 'WSRegisterCustomPage';
Begin Result := False; End;
Function WSRegisterCustomNotebook: Boolean; Public Name 'WSRegisterCustomNotebook';
Begin Result := False; End;
Function WSRegisterCustomShape: Boolean; Public Name 'WSRegisterCustomShape';
Begin Result := False; End;
Function WSRegisterCustomSplitter: Boolean; Public Name 'WSRegisterCustomSplitter';
Begin Result := False; End;
Function WSRegisterPaintBox: Boolean; Public Name 'WSRegisterPaintBox';
Begin Result := False; End;
Function WSRegisterCustomImage: Boolean; Public Name 'WSRegisterCustomImage';
Begin Result := False; End;
Function WSRegisterBevel: Boolean; Public Name 'WSRegisterBevel';
Begin Result := False; End;
Function WSRegisterCustomRadioGroup: Boolean; Public Name 'WSRegisterCustomRadioGroup';
Begin Result := False; End;
Function WSRegisterCustomCheckGroup: Boolean; Public Name 'WSRegisterCustomCheckGroup';
Begin Result := False; End;
Function WSRegisterCustomLabeledEdit: Boolean; Public Name 'WSRegisterCustomLabeledEdit';
Begin Result := False; End;
Function WSRegisterCustomPanel: Boolean; Public Name 'WSRegisterCustomPanel';
Begin Result := False; End;
Function WSRegisterCustomTrayIcon: Boolean; Public Name 'WSRegisterCustomTrayIcon';
Begin Result := False; End;
Function WSRegisterPreviewFileControl: Boolean; Public Name 'WSRegisterPreviewFileControl';
Begin Result := False; End;
Function WSRegisterPreviewFileDialog: Boolean; Public Name 'WSRegisterPreviewFileDialog';
Begin Result := False; End;
Function WSRegisterOpenPictureDialog: Boolean; Public Name 'WSRegisterOpenPictureDialog';
Begin Result := False; End;
Function WSRegisterSavePictureDialog: Boolean; Public Name 'WSRegisterSavePictureDialog';
Begin Result := False; End;
Function WSRegisterCalculatorDialog: Boolean; Public Name 'WSRegisterCalculatorDialog';
Begin Result := False; End;
Function WSRegisterCalculatorForm: Boolean; Public Name 'WSRegisterCalculatorForm';
Begin Result := False; End;
Function WSRegisterCalendarDialog: Boolean; Public Name 'WSRegisterCalendarDialog';
Begin Result := False; End;
Function WSRegisterCustomBitBtn: Boolean; Public Name 'WSRegisterCustomBitBtn';
Begin Result := False; End;
Function WSRegisterCustomSpeedButton: Boolean; Public Name 'WSRegisterCustomSpeedButton';
Begin Result := False; End;
Function WSRegisterCustomCheckListBox: Boolean; Public Name 'WSRegisterCustomCheckListBox';
Begin Result := False; End;
Function WSRegisterScrollingWinControl: Boolean; Public Name 'WSRegisterScrollingWinControl';
Begin Result := False; End;
Function WSRegisterScrollBox: Boolean; Public Name 'WSRegisterScrollBox';
Begin Result := False; End;
Function WSRegisterCustomFrame: Boolean; Public Name 'WSRegisterCustomFrame';
Begin Result := False; End;
Function WSRegisterCustomForm: Boolean; Public Name 'WSRegisterCustomForm';
Begin Result := False; End;
Function WSRegisterHintWindow: Boolean; Public Name 'WSRegisterHintWindow';
Begin Result := False; End;
Function WSRegisterCustomGrid: Boolean; Public Name 'WSRegisterCustomGrid';
Begin Result := False; End;
Function WSRegisterMenuItem: Boolean; Public Name 'WSRegisterMenuItem';
Begin Result := False; End;
Function WSRegisterMenu: Boolean; Public Name 'WSRegisterMenu';
Begin Result := False; End;
Function WSRegisterMainMenu: Boolean; Public Name 'WSRegisterMainMenu';
Begin Result := False; End;
Function WSRegisterPopupMenu: Boolean; Public Name 'WSRegisterPopupMenu';
Begin Result := False; End;
Function WSRegisterPairSplitterSide: Boolean; Public Name 'WSRegisterPairSplitterSide';
Begin Result := False; End;
Function WSRegisterCustomPairSplitter: Boolean; Public Name 'WSRegisterCustomPairSplitter';
Begin Result := False; End;
Function WSRegisterCustomFloatSpinEdit: Boolean; Public Name 'WSRegisterCustomFloatSpinEdit';
Begin Result := False; End;
Function WSRegisterCustomRubberBand: Boolean; Public Name 'WSRegisterCustomRubberBand';
Begin Result := False; End;
Function WSRegisterCustomShellTreeView: Boolean; Public Name 'WSRegisterCustomShellTreeView';
Begin Result := False; End;
Function WSRegisterCustomShellListView: Boolean; Public Name 'WSRegisterCustomShellListView';
Begin Result := False; End;
Function WSRegisterLazDeviceAPIs: Boolean; Public Name 'WSRegisterLazDeviceAPIs';
Begin Result := False; End;

End.
