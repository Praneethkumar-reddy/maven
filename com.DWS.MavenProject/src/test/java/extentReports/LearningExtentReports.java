package extentReports;

import java.io.File;
import java.io.IOException;
import java.time.Duration;
import java.time.LocalDateTime;

import org.openqa.selenium.By;
import org.openqa.selenium.OutputType;
import org.openqa.selenium.TakesScreenshot;
import org.openqa.selenium.WebDriver;
import org.openqa.selenium.chrome.ChromeDriver;
import org.openqa.selenium.io.FileHandler;

import com.aventstack.extentreports.ExtentReports;
import com.aventstack.extentreports.ExtentTest;
import com.aventstack.extentreports.MediaEntityBuilder;
import com.aventstack.extentreports.Status;
import com.aventstack.extentreports.reporter.ExtentSparkReporter;

import genericLibrary.BaseTest;

public class LearningExtentReports {
	static WebDriver driver;
	public static void main(String[] args) {
		ExtentSparkReporter reporter=new ExtentSparkReporter("./Reports/firstReport.html");
		ExtentReports report =new ExtentReports();
		report.attachReporter(reporter);
		ExtentTest test = report.createTest("LoginTest");
		System.setProperty("webdriver.chrome.driver", "./src/main/resources/Drivers/chromedriver.exe");
		driver=new ChromeDriver(); 
		driver.manage().window().maximize();
		driver.manage().timeouts().implicitlyWait(Duration.ofSeconds(10));
		driver.get("http://demowebshop.tricentis.com/");
		test.log(Status.INFO, "WebPage is loaded");
		driver.findElement(By.className("ico-login")).click();
		test.log(Status.INFO,"Login page is displayed");
		driver.findElement(By.id("Email")).sendKeys("yogbelavanaki@gmail.com");
		driver.findElement(By.id("Password")).sendKeys("Pssword@123");
		driver.findElement(By.xpath("//input[@value='Log in']")).click();
		try {
		if(driver.findElement(By.className("ico-logout")).isDisplayed()) {
			System.out.println("PASS: User is logged in"); 
			test.log(Status.PASS, "User has logged in successfully");
			test.pass(MediaEntityBuilder.createScreenCaptureFromPath(getScreenshot()).build());
		} 
		}catch(Exception e) {
			System.out.println("FAIL: User is not logged in");
			test.log(Status.FAIL, "USer has not logged in");
			test.fail(MediaEntityBuilder.createScreenCaptureFromPath(getScreenshot()).build());
		}
		driver.quit();	
		report.flush();
	}
	/**
	 * This method takes screenshot when invoked as well as returns the path of the 
	 * screenshot in the form of String
	 * @return
	 */
	public static String getScreenshot() {
		LocalDateTime dateTime=LocalDateTime.now();
		String dataStamp=dateTime.toString().replaceAll(":", "-");
		String path="./Screenshots/"+dataStamp+".png";
		TakesScreenshot ts = (TakesScreenshot) driver;
		File temp = ts.getScreenshotAs(OutputType.FILE);
		File dest=new File(path);
		try {
			FileHandler.copy(temp, dest);
		} catch (IOException e) {
			e.printStackTrace();
		}
		return "."+path;
	}


}
