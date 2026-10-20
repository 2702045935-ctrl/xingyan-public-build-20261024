import Foundation
import UIKit

enum WebSafeArea {

    static var js: String {
        let top = Int(max(0, L.safeTop).rounded())
        let bottom = Int(max(0, L.safeBottom).rounded())
        return """
        (function () {
          var st = \(top), sb = \(bottom);
          function apply() {
            var d = document.documentElement, b = document.body;
            if (d && d.style) {
              d.style.setProperty('--chris-safe-top', st + 'px');
              d.style.setProperty('--chris-safe-bottom', sb + 'px');
            }
            if (b && b.style) {
              if (st > 0) b.style.paddingTop = st + 'px';
              if (sb > 0) b.style.paddingBottom = sb + 'px';
              b.style.boxSizing = 'border-box';
            }
          }
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', apply);
          } else {
            apply();
          }
          window.addEventListener('load', apply);
          window.chrisSafeArea = function () { apply(); return { top: st, bottom: sb }; };
        })();
        """
    }
}
