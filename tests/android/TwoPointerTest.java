package arrowflow.qa;

import android.graphics.Point;
import com.android.uiautomator.core.UiObject;
import com.android.uiautomator.core.UiSelector;
import com.android.uiautomator.testrunner.UiAutomatorTestCase;

public class TwoPointerTest extends UiAutomatorTestCase {
    public void testSimultaneousContacts() {
        int x = Integer.parseInt(getParams().getString("x"));
        int y = Integer.parseInt(getParams().getString("y"));
        UiObject game = new UiObject(new UiSelector().packageName("com.romiqolab.arrowflow"));
        assertTrue("Game must be in foreground", game.exists());
        Point first = new Point(x, y);
        Point second = new Point(x - 100, y - 120);
        assertTrue("Inject two stationary contacts", game.performTwoPointerGesture(first, second, first, second, 20));
        System.out.println("ARROW_FLOW_TWO_POINTERS_INJECTED");
    }
}
