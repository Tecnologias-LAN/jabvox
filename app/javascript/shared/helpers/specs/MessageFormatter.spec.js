import MessageFormatter from '../MessageFormatter';

describe('#MessageFormatter', () => {
  describe('content with links', () => {
    it('should format correctly', () => {
      const message =
        'Jabvox is an opensource tool. [Jabvox](https://www.jabvox.com)';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        '<p>Jabvox is an opensource tool. <a href="https://www.jabvox.com" class="link" rel="noreferrer noopener nofollow" target="_blank">Jabvox</a></p>'
      );
    });
    it('should format correctly', () => {
      const message = 'Jabvox is an opensource tool. https://www.jabvox.com';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        '<p>Jabvox is an opensource tool. <a href="https://www.jabvox.com" class="link" rel="noreferrer noopener nofollow" target="_blank">https://www.jabvox.com</a></p>'
      );
    });
    it('should not convert template variables to links when linkify is disabled', () => {
      const message = 'Hey {{customer.name}}, check https://jabvox.com';
      const formatter = new MessageFormatter(message, false, false, false);
      expect(formatter.formattedMessage).toMatch(
        '<p>Hey {{customer.name}}, check https://jabvox.com</p>'
      );
    });
  });

  describe('parses heading to strong', () => {
    it('should format correctly', () => {
      const message = '### opensource \n ## tool';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        `<h3>opensource</h3>
<h2>tool</h2>`
      );
    });

    it('should not render a setext heading when text is followed by "--"', () => {
      const message = 'hy\n\n\\\n\\-\\-\n\nHello there';
      const result = new MessageFormatter(message).formattedMessage;
      expect(result).not.toMatch('<h2>');
      expect(result).not.toMatch('<h1>');
    });
  });

  describe('content with image and has "cw_image_height" query at the end of URL', () => {
    it('should set image height correctly', () => {
      const message =
        'Jabvox is an opensource tool. ![](http://jabvox.com/jabvox.png?cw_image_height=24px)';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        '<p>Jabvox is an opensource tool. <img src="http://jabvox.com/jabvox.png?cw_image_height=24px" alt="" style="height: 24px;" /></p>'
      );
    });

    it('should set image height correctly if its original size', () => {
      const message =
        'Jabvox is an opensource tool. ![](http://jabvox.com/jabvox.png?cw_image_height=auto)';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        '<p>Jabvox is an opensource tool. <img src="http://jabvox.com/jabvox.png?cw_image_height=auto" alt="" style="height: auto;" /></p>'
      );
    });

    it('should not set height', () => {
      const message =
        'Jabvox is an opensource tool. ![](http://jabvox.com/jabvox.png)';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        '<p>Jabvox is an opensource tool. <img src="http://jabvox.com/jabvox.png" alt="" /></p>'
      );
    });
  });

  describe('#disableImageRendering', () => {
    it('omits nested and reference images with relative URLs', () => {
      const message = `Before ![nested [alt]](/relative.png)

![reference][logo]

[logo]: /logo.png

After`;
      const formatter = new MessageFormatter(message);

      formatter.disableImageRendering();

      expect(formatter.formattedMessage).not.toContain('<img');
      expect(formatter.formattedMessage).toContain('Before');
      expect(formatter.formattedMessage).toContain('After');
    });
  });

  describe('tweets', () => {
    it('should return the same string if not tags or @mentions', () => {
      const message = 'Jabvox is an opensource tool';
      expect(new MessageFormatter(message).formattedMessage).toMatch(message);
    });

    it('should add links to @mentions', () => {
      const message =
        '@jabvoxapp is an opensource tool thanks @longnonexistenttwitterusername';
      expect(
        new MessageFormatter(message, true, false).formattedMessage
      ).toMatch(
        '<p><a href="http://twitter.com/jabvoxapp" class="link" rel="noreferrer noopener nofollow" target="_blank">@jabvoxapp</a> is an opensource tool thanks @longnonexistenttwitterusername</p>'
      );
    });

    it('should add links to #tags', () => {
      const message = '#jabvoxapp is an opensource tool';
      expect(
        new MessageFormatter(message, true, false).formattedMessage
      ).toMatch(
        '<p><a href="https://twitter.com/hashtag/jabvoxapp" class="link" rel="noreferrer noopener nofollow" target="_blank">#jabvoxapp</a> is an opensource tool</p>'
      );
    });
  });

  describe('private notes', () => {
    it('should return the same string if not tags or @mentions', () => {
      const message = 'Jabvox is an opensource tool';
      expect(new MessageFormatter(message).formattedMessage).toMatch(message);
    });

    it('should add links to @mentions', () => {
      const message =
        '@jabvoxapp is an opensource tool thanks @longnonexistenttwitterusername';
      expect(
        new MessageFormatter(message, false, true).formattedMessage
      ).toMatch(message);
    });

    it('should add links to #tags', () => {
      const message = '#jabvoxapp is an opensource tool';
      expect(
        new MessageFormatter(message, false, true).formattedMessage
      ).toMatch(message);
    });
  });

  describe('plain text content', () => {
    it('returns the plain text without HTML', () => {
      const message =
        '<b>Jabvox is an opensource tool. https://www.jabvox.com</b>';
      expect(new MessageFormatter(message).plainText).toMatch(
        'Jabvox is an opensource tool. https://www.jabvox.com'
      );
    });
  });

  describe('help center table colwidth marker', () => {
    it('strips the internal colwidths marker from rendered output', () => {
      const message =
        '<!--cw-colwidths:120,200-->\n| A | B |\n| --- | --- |\n| 1 | 2 |';
      const formatter = new MessageFormatter(message);
      expect(formatter.formattedMessage).not.toContain('cw-colwidths');
      expect(formatter.plainText).not.toContain('cw-colwidths');
    });

    it('strips a blockquote-prefixed marker so the quoted table still renders', () => {
      const message =
        '> <!--cw-colwidths:120,200-->\n> | A | B |\n> | --- | --- |\n> | 1 | 2 |';
      const { formattedMessage } = new MessageFormatter(message);
      expect(formattedMessage).not.toContain('cw-colwidths');
      expect(formattedMessage).toContain('<blockquote>');
      expect(formattedMessage).toContain('<table>');
    });
  });

  describe('#sanitize', () => {
    it('sanitizes markup and removes all unnecessary elements', () => {
      const message =
        '[xssLink](javascript:alert(document.cookie))\n[normalLink](https://google.com)**I am a bold text paragraph**';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        `<p>[xssLink](javascript:alert(document.cookie))<br />
<a href="https://google.com" class="link" rel="noreferrer noopener nofollow" target="_blank">normalLink</a><strong>I am a bold text paragraph</strong></p>`
      );
    });
  });
});
