package pomRepo;

import org.openqa.selenium.WebDriver;
import org.openqa.selenium.WebElement;
import org.openqa.selenium.support.FindBy;
import org.openqa.selenium.support.PageFactory;

public class RegisterPage {
	
	public RegisterPage(WebDriver driver) {
		PageFactory.initElements(driver, /*point to current page*/this );
	}
	
	@FindBy(id="gender-male")
	WebElement maleRadioButton;

	public void clickMaleRadioButton() {
		maleRadioButton.click();
	}
	
	@FindBy(id="gender-female")
	WebElement femaleRadioButton;
	
	public void clickFemaleRadioButton() {
		femaleRadioButton.click();
	}
	
	@FindBy(id = "FirstName")
	WebElement firstNameTextField;
	
	public void enterFirstName(String firstName) {
		firstNameTextField.sendKeys(firstName);
	}
	
	@FindBy(xpath = "(//input[@value='Register'])[1]")
	WebElement registerButton;
	
	public void clickRegisterButton() {
		registerButton.click();
	}
	
}
