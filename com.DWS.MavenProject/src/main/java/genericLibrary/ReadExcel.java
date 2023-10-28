package genericLibrary;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;

import org.apache.poi.EncryptedDocumentException;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.ss.usermodel.WorkbookFactory;

public class ReadExcel {
	public static String singleRead(String sheetName, int rowNum, int colNum) throws EncryptedDocumentException, IOException {
		File file=new File("./Data/TestData.xlsx");
		FileInputStream fis=new FileInputStream(file);
		Workbook workbook=WorkbookFactory.create(fis);
		Sheet sheet=workbook.getSheet(sheetName);
		return sheet.getRow(rowNum).getCell(colNum).toString();
	}

	public static Object[][] /*void*/ multipleRead(String sheetName) throws EncryptedDocumentException, IOException {
		File file=new File("./Data/TestData.xlsx");
		FileInputStream fis=new FileInputStream(file);
		Workbook workbook=WorkbookFactory.create(fis);
		Sheet sheet=workbook.getSheet(sheetName);
		int rowNum=sheet.getPhysicalNumberOfRows();
		int colNum=sheet.getRow(0).getPhysicalNumberOfCells();
		
		Object[][] data=new Object[rowNum-1][colNum];
		for (int i = 1; i < rowNum; i++) {
			for (int j = 0; j < colNum; j++) {
				data[i-1][j]=sheet.getRow(i).getCell(j).toString();
			}
		}
		return data;
	}


}
