module CloudModel
  module Components
    # The Puppeteer/headless-Chromium runtime stack: Node.js (pulled in via
    # {#requirements}) plus the Chromium shared libraries. Apps that render HTML
    # to PDF/PNG through Puppeteer (e.g. via the grover gem) need this at
    # *runtime* — grover spawns node to drive the Chromium the build bundled
    # into the artifact — so it is an opt-in runtime component, added to a web
    # image's additional_components rather than baked into the base Ruby stack.
    class PuppeteerComponent < BaseComponent
      def human_name
        "Puppeteer/Chromium #{version}".strip
      end

      def requirements
        [:nodejs]
      end
    end
  end
end
