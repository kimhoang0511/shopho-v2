const CONTACT_EMAIL = 'kimhoang05111@gmail.com'

export default function PrivacyPage() {
    return (
        <div style={styles.page}>
            <div style={styles.container}>
                <div style={styles.logo}>
                    <img src="/logo.png" alt="Kinme" style={styles.logoImg} />
                    <span style={styles.logoText}>Kinme</span>
                </div>

                <h1 style={styles.title}>Chính sách quyền riêng tư</h1>
                <p style={styles.updated}>Cập nhật lần cuối: 14 tháng 5, 2026</p>

                <section style={styles.section}>
                    <p style={styles.intro}>
                        Ứng dụng <strong>Kinme</strong> ("chúng tôi", "ứng dụng") cam kết bảo vệ quyền riêng tư của bạn.
                        Chính sách này mô tả cách chúng tôi thu thập, sử dụng và bảo vệ thông tin cá nhân của bạn
                        khi sử dụng ứng dụng Kinme.
                    </p>
                </section>

                <section style={styles.section}>
                    <h2 style={styles.h2}>1. Thông tin chúng tôi thu thập</h2>

                    <h3 style={styles.h3}>a) Thông tin bạn cung cấp trực tiếp</h3>
                    <ul style={styles.ul}>
                        <li style={styles.li}><strong>Thông tin tài khoản:</strong> Họ tên, số điện thoại, email, ảnh đại diện khi bạn đăng ký tài khoản.</li>
                        <li style={styles.li}><strong>Thông tin đơn hàng:</strong> Tiêu đề, mô tả, địa chỉ, hình ảnh liên quan đến đơn hàng bạn tạo hoặc nhận.</li>
                        <li style={styles.li}><strong>Thông tin ngân hàng:</strong> Số tài khoản ngân hàng, tên chủ tài khoản, tên ngân hàng để người đặt đơn chuyển khoản</li>
                    </ul>

                    <h3 style={styles.h3}>b) Thông tin thu thập tự động</h3>
                    <ul style={styles.ul}>
                        <li style={styles.li}><strong>Thông tin thiết bị:</strong> Loại thiết bị, hệ điều hành, phiên bản ứng dụng.</li>
                        <li style={styles.li}><strong>Vị trí:</strong> Vị trí hiện tại của bạn để hiển thị đơn hàng gần đó và kết nối với người giúp đỡ trong khu vực.</li>
                        <li style={styles.li}><strong>Token thiết bị:</strong> Để gửi thông báo đẩy (push notifications) về đơn hàng, tin nhắn và cuộc gọi.</li>
                    </ul>
                </section>

                <section style={styles.section}>
                    <h2 style={styles.h2}>2. Cách chúng tôi sử dụng thông tin</h2>
                    <ul style={styles.ul}>
                        <li style={styles.li}>Cung cấp và duy trì dịch vụ kết nối người cần giúp và người giúp đỡ trong khu căn hộ, khu tập thể.</li>
                        <li style={styles.li}>Xử lý tạo đơn hàng, nhận đơn hàng và quản lý trạng thái đơn hàng.</li>
                        <li style={styles.li}>Hỗ trợ tính năng gọi thoại và nhắn tin trực tiếp giữa người dùng.</li>
                        <li style={styles.li}>Quản lý hệ thống nạp lượt và thanh toán qua chuyển khoản ngân hàng.</li>
                        <li style={styles.li}>Gửi thông báo về đơn hàng, tin nhắn, cuộc gọi và cập nhật ứng dụng.</li>
                        <li style={styles.li}>Cải thiện trải nghiệm người dùng và chất lượng dịch vụ.</li>
                        <li style={styles.li}>Ngăn chặn hành vi gian lận, lạm dụng hoặc vi phạm điều khoản sử dụng.</li>
                    </ul>
                </section>

                <section style={styles.section}>
                    <h2 style={styles.h2}>3. Chia sẻ thông tin</h2>
                    <p style={styles.p}>Chúng tôi <strong>không bán</strong> thông tin cá nhân của bạn cho bên thứ ba. Chúng tôi chỉ chia sẻ thông tin trong các trường hợp sau:</p>
                    <ul style={styles.ul}>
                        <li style={styles.li}><strong>Giữa người dùng:</strong> Khi bạn tạo hoặc nhận đơn hàng, thông tin cần thiết (họ tên, số điện thoại, địa chỉ) sẽ được hiển thị cho bên liên quan để hoàn thành đơn hàng.</li>
                        <li style={styles.li}><strong>Nhà cung cấp dịch vụ:</strong> Firebase (Google) để xác thực, lưu trữ dữ liệu và gửi thông báo; LiveKit để hỗ trợ gọi thoại.</li>
                        <li style={styles.li}><strong>Yêu cầu pháp lý:</strong> Khi có yêu cầu từ cơ quan chức năng theo quy định pháp luật.</li>
                    </ul>
                </section>

                <section style={styles.section}>
                    <h2 style={styles.h2}>4. Lưu trữ và bảo mật dữ liệu</h2>
                    <ul style={styles.ul}>
                        <li style={styles.li}>Dữ liệu được lưu trữ trên máy chủ bảo mật và được mã hóa khi truyền tải (HTTPS/SSL).</li>
                        <li style={styles.li}>Mật khẩu được mã hóa (hash) và không lưu dưới dạng văn bản rõ.</li>
                        <li style={styles.li}>Chúng tôi áp dụng các biện pháp bảo mật phù hợp để bảo vệ dữ liệu khỏi truy cập trái phép.</li>
                        <li style={styles.li}>Dữ liệu được lưu trữ trong thời gian cần thiết để cung cấp dịch vụ hoặc theo yêu cầu pháp luật.</li>
                    </ul>
                </section>

                <section style={styles.section}>
                    <h2 style={styles.h2}>5. Quyền của bạn</h2>
                    <ul style={styles.ul}>
                        <li style={styles.li}><strong>Truy cập:</strong> Bạn có thể xem thông tin cá nhân của mình trong phần Hồ sơ tài khoản.</li>
                        <li style={styles.li}><strong>Chỉnh sửa:</strong> Bạn có thể cập nhật họ tên, ảnh đại diện và thông tin ngân hàng bất cứ lúc nào.</li>
                        <li style={styles.li}><strong>Xóa tài khoản:</strong> Bạn có thể yêu cầu xóa tài khoản. Thông tin cá nhân sẽ bị ẩn, nhưng dữ liệu liên quan đến đơn hàng đã hoàn thành có thể được giữ lại theo quy định pháp luật.</li>
                        <li style={styles.li}><strong>Thu hồi đồng ý:</strong> Bạn có thể tắt thông báo đẩy và chia sẻ vị trí trong cài đặt thiết bị.</li>
                    </ul>
                </section>

                <section style={styles.section}>
                    <h2 style={styles.h2}>6. Quyền riêng tư của trẻ em</h2>
                    <p style={styles.p}>
                        Ứng dụng Kinme không dành cho trẻ em dưới 18 tuổi. Chúng tôi không cố ý thu thập thông tin cá nhân từ trẻ em dưới 18 tuổi.
                        Nếu phát hiện thu thập dữ liệu từ trẻ em dưới 18 tuổi, chúng tôi sẽ xóa ngay lập tức.
                    </p>
                </section>

                <section style={styles.section}>
                    <h2 style={styles.h2}>7. Thông báo đẩy và cuộc gọi</h2>
                    <p style={styles.p}>
                        Ứng dụng sử dụng Firebase Cloud Messaging (FCM) và LiveKit để gửi thông báo và hỗ trợ gọi thoại.
                        Bạn có thể quản lý tùy chọn thông báo trong cài đặt thiết bị.
                    </p>
                </section>

                <section style={styles.section}>
                    <h2 style={styles.h2}>8. Liên kết bên ngoài</h2>
                    <p style={styles.p}>
                        Ứng dụng có thể chứa liên kết đến trang web hoặc dịch vụ bên ngoài. Chúng tôi không chịu trách nhiệm
                        về chính sách quyền riêng tư của các trang web bên thứ ba.
                    </p>
                </section>

                <section style={styles.section}>
                    <h2 style={styles.h2}>9. Thay đổi chính sách</h2>
                    <p style={styles.p}>
                        Chúng tôi có thể cập nhật chính sách này theo thời gian. Mọi thay đổi sẽ được thông báo qua ứng dụng
                        hoặc email. Việc tiếp tục sử dụng ứng dụng sau khi thay đổi đồng nghĩa với việc bạn chấp nhận chính sách mới.
                    </p>
                </section>

                <section style={styles.section}>
                    <h2 style={styles.h2}>10. Liên hệ</h2>
                    <p style={styles.p}>
                        Nếu bạn có câu hỏi hoặc yêu cầu liên quan đến chính sách quyền riêng tư, vui lòng liên hệ:
                    </p>
                    <div style={styles.contactBox}>
                        <p style={styles.contactItem}>📧 Email: <a href={`mailto:${CONTACT_EMAIL}`} style={styles.link}>{CONTACT_EMAIL}</a></p>
                        <p style={styles.contactItem}>📱 Tên ứng dụng: <strong>Kinme</strong></p>
                    </div>
                </section>

                <div style={styles.footer}>
                    <p style={styles.footerText}>© 2026 Kinme. Bảo lưu mọi quyền.</p>
                </div>
            </div>
        </div>
    )
}

const styles = {
    page: {
        minHeight: '100vh',
        background: 'linear-gradient(135deg, #f5f7ff 0%, #f0f2f8 100%)',
        padding: '0',
    },
    container: {
        maxWidth: 720,
        margin: '0 auto',
        padding: '40px 20px 60px',
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
        color: '#1a1a2e',
        lineHeight: 1.7,
    },
    logo: {
        display: 'flex',
        alignItems: 'center',
        gap: 10,
        marginBottom: 24,
    },
    logoImg: {
        width: 40,
        height: 40,
        borderRadius: 10,
        objectFit: 'cover',
    },
    logoText: {
        fontWeight: 700,
        fontSize: 20,
        color: '#5B6AF0',
    },
    title: {
        fontSize: 28,
        fontWeight: 800,
        color: '#1a1a2e',
        marginBottom: 6,
    },
    updated: {
        fontSize: 13,
        color: '#888',
        marginBottom: 32,
    },
    section: {
        marginBottom: 28,
    },
    intro: {
        fontSize: 15,
        color: '#444',
        lineHeight: 1.8,
    },
    h2: {
        fontSize: 18,
        fontWeight: 700,
        color: '#1a1a2e',
        marginBottom: 12,
        paddingBottom: 6,
        borderBottom: '2px solid #e8e8f0',
    },
    h3: {
        fontSize: 15,
        fontWeight: 600,
        color: '#333',
        marginTop: 14,
        marginBottom: 8,
    },
    p: {
        fontSize: 14,
        color: '#444',
        lineHeight: 1.8,
        marginBottom: 8,
    },
    ul: {
        paddingLeft: 20,
        margin: '8px 0',
    },
    li: {
        fontSize: 14,
        color: '#444',
        lineHeight: 1.8,
        marginBottom: 6,
    },
    contactBox: {
        background: '#f4f5ff',
        borderRadius: 12,
        padding: '16px 20px',
        marginTop: 12,
    },
    contactItem: {
        fontSize: 14,
        color: '#444',
        marginBottom: 4,
    },
    link: {
        color: '#5B6AF0',
        textDecoration: 'none',
        fontWeight: 600,
    },
    footer: {
        marginTop: 40,
        paddingTop: 20,
        borderTop: '1px solid #e8e8f0',
        textAlign: 'center',
    },
    footerText: {
        fontSize: 12,
        color: '#aaa',
    },
}